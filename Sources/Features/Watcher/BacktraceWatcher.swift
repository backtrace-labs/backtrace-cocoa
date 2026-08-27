import Foundation

final class BacktraceWatcher<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceReport {

    let settings: BacktraceDatabaseSettings
    let api: BacktraceApi
    let repository: BacktraceRepository
    var timer: DispatchSourceTimer?
    let queue: DispatchQueue
    let networkAvailabilityCheck: () -> Bool
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false

    init(settings: BacktraceDatabaseSettings,
         api: BacktraceApi,
         repository: BacktraceRepository,
         dispatchQueue: DispatchQueue = DispatchQueue(label: "backtrace.timer", qos: .background),
         networkAvailabilityCheck: (() -> Bool)? = nil) {

        self.settings = settings
        self.repository = repository
        self.api = api
        self.queue = dispatchQueue
        self.networkAvailabilityCheck = networkAvailabilityCheck ?? api.networkClient.isNetworkAvailable
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

    internal func batchRetry() {
        guard !isShutdown else { return }
        guard settings.retryBehaviour == .interval else { return }
        guard networkAvailabilityCheck() else { return }
        guard let reports = try? reportsFromRepository(limit: 10), !reports.isEmpty else { return }
        BacktraceLogger.debug("Resending reporting. Batch size: \(reports.count)")

        for report in reports {
            guard !isShutdown else { return }
            let result: BacktraceResult
            do {
                result = try api.send(report)
            } catch {
                guard !isShutdown else { return }
                handleSubmissionFailure(error, for: report)
                continue
            }
            guard !isShutdown else { return }
            guard handleSubmissionResult(result, for: report) else { return }
        }
    }

    private func handleSubmissionResult(_ result: BacktraceResult,
                                        for report: BacktraceReport) -> Bool {
        guard !isShutdown else { return false }
        switch result.submissionDisposition {
        case .accepted:
            finishTerminalReport(report)
        case .rateLimited:
            // Every remaining report shares this limiter, so avoid duplicate limit callbacks.
            return false
        case .retryable:
            do {
                try repository.incrementRetryCount(report, limit: settings.retryLimit)
            } catch {
                guard !isShutdown else { return false }
                BacktraceLogger.error("Unable to update retry state for report \(report.identifier)")
            }
        case .permanentFailure:
            BacktraceLogger.error(
                "Report \(report.identifier) was permanently rejected and will not be retried")
            finishTerminalReport(report)
        }
        return true
    }

    private func finishTerminalReport(_ report: BacktraceReport) {
        guard !isShutdown else { return }
        do {
            try repository.markTerminalForDeletion(report)
        } catch {
            guard !isShutdown else { return }
            BacktraceLogger.error("Unable to persist terminal state for report \(report.identifier)")
            do {
                try repository.delete(report)
            } catch {
                guard !isShutdown else { return }
                BacktraceLogger.error("Unable to remove terminal report \(report.identifier)")
            }
            return
        }

        guard !isShutdown else { return }
        do {
            try repository.delete(report)
        } catch {
            guard !isShutdown else { return }
            BacktraceLogger.warning("Deferred cleanup of terminal report \(report.identifier)")
        }
    }

    private func handleSubmissionFailure(_ error: Error, for report: BacktraceReport) {
        guard !isShutdown else { return }
        if error.backtraceSubmissionDisposition == .permanentFailure {
            BacktraceLogger.error(
                "Report \(report.identifier) has a permanent submission configuration error " +
                "and will not be retried")
            finishTerminalReport(report)
        } else {
            BacktraceLogger.error("Retry submission for report \(report.identifier) failed")
            try? repository.incrementRetryCount(report, limit: settings.retryLimit)
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
        batchRetry()
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
        lifecycleLock.unlock()
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
