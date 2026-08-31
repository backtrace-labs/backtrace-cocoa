import Foundation

final class BacktraceWatcher<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceReport {

    private struct RetrySnapshot {
        let reports: [BacktraceReport]
    }

    internal enum InitialBatchResult: Equatable {
        case empty
        case progressed
        case rateLimited
        case stopped
    }

    let settings: BacktraceDatabaseSettings
    let submissionCoordinator: BacktraceSubmissionCoordinator<BacktraceRepository>
    var api: BacktraceApi { submissionCoordinator.api }
    let repository: BacktraceRepository
    var timer: DispatchSourceTimer?
    let queue: DispatchQueue
    let networkAvailabilityCheck: () -> Bool
    private let initialAdmissionScheduler: (TimeInterval, DispatchWorkItem) -> Void
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false
    private var initialAdmissionWorkItem: DispatchWorkItem?

    init(settings: BacktraceDatabaseSettings,
         submissionCoordinator: BacktraceSubmissionCoordinator<BacktraceRepository>,
         repository: BacktraceRepository,
         dispatchQueue: DispatchQueue = DispatchQueue(label: "backtrace.timer", qos: .background),
         networkAvailabilityCheck: (() -> Bool)? = nil,
         initialAdmissionScheduler: ((TimeInterval, DispatchWorkItem) -> Void)? = nil) {

        self.settings = settings
        self.repository = repository
        self.submissionCoordinator = submissionCoordinator
        self.queue = dispatchQueue
        self.networkAvailabilityCheck = networkAvailabilityCheck ??
            submissionCoordinator.api.networkClient.isNetworkAvailable
        self.initialAdmissionScheduler = initialAdmissionScheduler ?? { delay, workItem in
            dispatchQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    /// Source-compatible convenience for tests and internal callers that do not share a coordinator with live/OOM submission.
    convenience init(settings: BacktraceDatabaseSettings,
                     api: BacktraceApi,
                     repository: BacktraceRepository,
                     dispatchQueue: DispatchQueue = DispatchQueue(label: "backtrace.timer", qos: .background),
                     networkAvailabilityCheck: (() -> Bool)? = nil,
                     initialAdmissionScheduler: ((TimeInterval, DispatchWorkItem) -> Void)? = nil) {
        let coordinator = BacktraceSubmissionCoordinator(api: api,
                                                         repository: repository,
                                                         retryLimit: settings.retryLimit)
        self.init(settings: settings,
                  submissionCoordinator: coordinator,
                  repository: repository,
                  dispatchQueue: dispatchQueue,
                  networkAvailabilityCheck: networkAvailabilityCheck,
                  initialAdmissionScheduler: initialAdmissionScheduler)
    }

    internal var isShutdown: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }

    func enable() {
        guard settings.retryBehaviour == .interval else { return }
        configureTimer(with: DispatchWorkItem(block: timerEventHandler))
    }

    func replayAsync() {
        guard settings.retryBehaviour == .interval, !isShutdown else { return }
        startDeliveryAsync()
    }

    /// Starts one ordered delivery cycle. Eligible retry rows are snapshotted first,
    /// but initial native crashes always receive admission before that snapshot is submitted.
    func startDeliveryAsync() {
        guard !isShutdown else { return }
        let bypassesReachabilityPreflight = settings.retryBehaviour == .none
        queue.async { [weak self] in
            self?.runDeliveryCycle(
                bypassesReachabilityPreflight: bypassesReachabilityPreflight
            )
        }
    }

    /// Schedules the ordered cycle that provides newly ingested native crashes
    /// an initial opportunity independently from ordinary repository retry policy.
    func submitInitialAsync() {
        startDeliveryAsync()
    }

    /// Captures retry eligibility before initial delivery,
    /// then gives initial native crashes first use of shared rate-limit capacity.
    /// A failed initial report cannot appear in the already captured retry snapshot
    /// and cannot be replayed in this cycle.
    internal func runDeliveryCycle(bypassesReachabilityPreflight: Bool = false) {
        guard !isShutdown else { return }

        let retrySnapshot = captureRetrySnapshot()
        let initialResult = drainInitialSubmissions(
            bypassesReachabilityPreflight: bypassesReachabilityPreflight
        )

        switch initialResult {
        case .empty, .progressed:
            submitRetrySnapshot(retrySnapshot)
        case .rateLimited, .stopped:
            return
        }
    }

    @discardableResult
    internal func batchInitialSubmission(
        bypassesReachabilityPreflight: Bool = false
    ) -> InitialBatchResult {
        guard !isShutdown else { return .stopped }
        guard bypassesReachabilityPreflight || networkAvailabilityCheck() else { return .stopped }
        guard let reports = try? repository.getInitialSubmission(count: 10),
              !reports.isEmpty else { return .empty }

        var enteredPipeline = false
        var durableClaimContention = false

        for report in reports {
            guard !isShutdown else { return .stopped }
            let receipt = submissionCoordinator.submit(report, origin: .pendingNativeCrash)
            // Another process may claim one row after this page is fetched.
            // Continue with the rest of this snapshot;
            // a durable lost claim also permits the next bounded fetch because that row is no longer eligible in the shared store.
            guard receipt.pipelineEntered else {
                guard receipt.isDurable else { return .stopped }
                durableClaimContention = true
                continue
            }
            enteredPipeline = true
            if receipt.result.submissionDisposition == .rateLimited,
               !receipt.transportStarted {
                return .rateLimited
            }
        }
        if enteredPipeline {
            return .progressed
        }
        // A failed compare-and-swap means another process moved every contended row out of this eligible snapshot.
        // Refetch once so a later page is not stranded.
        return durableClaimContention ? .progressed : .empty
    }

    /// Drains bounded fetches until there is no initial work or local admission is full.
    /// Independent from ordinary repository replay and runs when `RetryBehaviour.none` is configured.
    @discardableResult
    internal func drainInitialSubmissions(
        bypassesReachabilityPreflight: Bool = false
    ) -> InitialBatchResult {
        // A pending admission wakeup owns the next available limiter slot.
        // A timer cycle arriving first must not let ordinary retries consume that slot.
        guard !hasScheduledInitialAdmission else { return .rateLimited }
        var madeProgress = false
        while !isShutdown {
            switch batchInitialSubmission(
                bypassesReachabilityPreflight: bypassesReachabilityPreflight
            ) {
            case .progressed:
                madeProgress = true
                continue
            case .rateLimited:
                scheduleInitialAdmissionCheck(
                    bypassesReachabilityPreflight: bypassesReachabilityPreflight
                )
                return .rateLimited
            case .empty:
                return madeProgress ? .progressed : .empty
            case .stopped:
                return .stopped
            }
        }
        return .stopped
    }

    internal func batchRetry() {
        submitRetrySnapshot(captureRetrySnapshot())
    }

    private func captureRetrySnapshot() -> RetrySnapshot {
        guard !isShutdown,
              settings.retryBehaviour == .interval,
              networkAvailabilityCheck(),
              let reports = try? reportsFromRepository(limit: 10) else {
            return RetrySnapshot(reports: [])
        }
        return RetrySnapshot(reports: reports)
    }

    private func submitRetrySnapshot(_ snapshot: RetrySnapshot) {
        guard !isShutdown,
              settings.retryBehaviour == .interval,
              networkAvailabilityCheck(),
              !snapshot.reports.isEmpty else { return }
        BacktraceLogger.debug("Resending reporting. Batch size: \(snapshot.reports.count)")

        for report in snapshot.reports {
            guard !isShutdown else { return }
            let receipt = submissionCoordinator.submit(report, origin: .repositoryRetry)
            guard receipt.pipelineEntered else { continue }
            if receipt.result.submissionDisposition == .rateLimited {
                // Every remaining report shares this limiter, so avoid duplicate limit callbacks.
                return
            }
        }
    }

    deinit {
        shutdown()
    }
}

// MARK: - Timer
extension BacktraceWatcher {

    internal func configureTimer(with handler: DispatchWorkItem) {
        lifecycleLock.lock()
        guard !shutdownRequested, timer == nil else {
            lifecycleLock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        let repeating: DispatchTimeInterval = .seconds(settings.retryInterval)
        timer.schedule(deadline: DispatchTime.now() + repeating, repeating: repeating)
        timer.setEventHandler(handler: handler)
        timer.resume()
        lifecycleLock.unlock()
    }

    internal func timerEventHandler() {
        runDeliveryCycle()
    }

    internal func resetTimer() {
        lifecycleLock.lock()
        let timerToCancel = timer
        timer = nil
        lifecycleLock.unlock()

        timerToCancel?.setEventHandler {}
        timerToCancel?.cancel()
    }

    /// Makes queued and in-flight replay continuations observe shutdown before transport cancellation can unblock them.
    /// This phase never waits for the replay queue.
    internal func prepareForShutdown() {
        lifecycleLock.lock()
        shutdownRequested = true
        let initialAdmissionToCancel = initialAdmissionWorkItem
        initialAdmissionWorkItem = nil
        lifecycleLock.unlock()

        initialAdmissionToCancel?.cancel()
    }

    /// Cancels the retry source after the transport has been cancelled.
    /// Keeping source teardown separate lets `BacktraceReporter` close producer races without delaying URLSession cancel.
    internal func finishShutdown() {
        lifecycleLock.lock()
        let timerToCancel = timer
        timer = nil
        lifecycleLock.unlock()

        timerToCancel?.setEventHandler {}
        timerToCancel?.cancel()
    }

    /// Stops timer and queued replay activity without releasing the repository or crash reporter.
    /// Safe to call repeatedly and deliberately non-blocking so a stalled transport cannot hang native bridge shutdown.
    /// Queued continuations observe `shutdownRequested` before mutating.
    internal func shutdown() {
        prepareForShutdown()
        finishShutdown()
    }
}

// MARK: - Initial admission
extension BacktraceWatcher {

    private var hasScheduledInitialAdmission: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return initialAdmissionWorkItem != nil
    }

    private func scheduleInitialAdmissionCheck(bypassesReachabilityPreflight: Bool) {
        guard let delay = api.backtraceRateLimiter.delayUntilNextAvailability() else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lifecycleLock.lock()
            self.initialAdmissionWorkItem = nil
            let shouldRun = !self.shutdownRequested
            self.lifecycleLock.unlock()
            guard shouldRun else { return }

            self.runDeliveryCycle(
                bypassesReachabilityPreflight: bypassesReachabilityPreflight
            )
        }

        lifecycleLock.lock()
        guard !shutdownRequested, initialAdmissionWorkItem == nil else {
            lifecycleLock.unlock()
            return
        }
        initialAdmissionWorkItem = workItem
        lifecycleLock.unlock()

        initialAdmissionScheduler(delay, workItem)
    }
}

// MARK: - Reports retrieving
extension BacktraceWatcher {

    // Takes from `repository` reports to send
    internal func reportsFromRepository(limit: Int) throws -> [BacktraceRepository.Resource] {
        switch settings.retryOrder {
        case .queue: return try repository.getOldest(count: limit)
        case .stack: return try repository.getLatest(count: limit)
        }
    }
}
