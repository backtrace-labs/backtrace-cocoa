import Foundation

final class BacktraceWatcher<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceReport {

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
        queue.async { [weak self] in
            self?.batchRetry()
        }
    }

    /// Schedules exactly one initial attempt for newly ingested native crashes,
    /// independently from ordinary repository retry policy.
    func submitInitialAsync() {
        guard !isShutdown else { return }
        // With retries disabled this is the process's only opportunity to submit a newly ingested native crash.
        // Reachability is advisory, so let the transport make that one decision.
        // Interval mode keeps its offline deferral because the timer will revisit the row later.
        let bypassesReachabilityPreflight = settings.retryBehaviour == .none
        queue.async { [weak self] in
            self?.drainInitialSubmissions(bypassesReachabilityPreflight: bypassesReachabilityPreflight)
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
    internal func drainInitialSubmissions(bypassesReachabilityPreflight: Bool = false) {
        guard !hasScheduledInitialAdmission else { return }
        while !isShutdown {
            switch batchInitialSubmission(
                bypassesReachabilityPreflight: bypassesReachabilityPreflight
            ) {
            case .progressed:
                continue
            case .rateLimited:
                scheduleInitialAdmissionCheck(
                    bypassesReachabilityPreflight: bypassesReachabilityPreflight
                )
                return
            case .empty, .stopped:
                return
            }
        }
    }

    internal func batchRetry() {
        guard !isShutdown else { return }
        guard settings.retryBehaviour == .interval else { return }
        guard networkAvailabilityCheck() else { return }
        guard let reports = try? reportsFromRepository(limit: 10), !reports.isEmpty else { return }
        BacktraceLogger.debug("Resending reporting. Batch size: \(reports.count)")

        for report in reports {
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
        // Retry rows that predate this tick first, then attempt newly discovered native rows.
        // If an initial attempt becomes retryable, it waits for the next interval instead of
        // being submitted twice in one timer cycle.
        batchRetry()
        drainInitialSubmissions()
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

            self.drainInitialSubmissions(
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
