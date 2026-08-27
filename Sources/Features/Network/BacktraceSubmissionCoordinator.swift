import Foundation

/// Identifies the lifecycle that produced a submission.
/// Persisted initial delivery is kept separate from repository retry so `RetryBehaviour.none` can still make one first attempt.
enum BacktraceSubmissionOrigin: Equatable {
    case live
    case pendingNativeCrash
    case repositoryRetry
    case outOfMemory
}

struct BacktraceSubmissionReceipt {
    let result: BacktraceResult
    let attempted: Bool
    /// True when the server outcome is terminal or the report is durably represented by the repository after this call.
    /// OOM cleanup relies on this value during shutdown races.
    let isDurable: Bool
}

/// Owns the boundary between a classified transport outcome and repository delivery state.
///
/// The API invokes this coordinator before post-response delegate callbacks.
/// During shutdown, new operations are rejected and unfinished transports are cancelled,
/// while operations that already received a response remain allowed to finish their local transaction.
final class BacktraceSubmissionCoordinator<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceReport {

    private enum LifecycleState {
        case active
        case quiescing
    }

    let api: BacktraceApi
    let repository: BacktraceRepository
    let retryLimit: Int

    private let lifecycleLock = NSLock()
    private var lifecycleState = LifecycleState.active
    private var activeSubmissions = 0
    private var transportCancellationStarted = false
    private var quiescenceCompletions: [() -> Void] = []

    /// Deterministic test barrier placed after classification and before durable finalization.
    internal var beforeFinalization: ((BacktraceSubmissionOutcome) -> Void)?

    init(api: BacktraceApi,
         repository: BacktraceRepository,
         retryLimit: Int,
         beforeFinalization: ((BacktraceSubmissionOutcome) -> Void)? = nil) {
        self.api = api
        self.repository = repository
        self.retryLimit = retryLimit
        self.beforeFinalization = beforeFinalization
    }

    internal var isQuiescing: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return lifecycleState == .quiescing
    }

    func submit(_ report: BacktraceReport,
                origin: BacktraceSubmissionOrigin) -> BacktraceSubmissionReceipt {
        guard beginSubmission() else {
            return BacktraceSubmissionReceipt(
                result: BacktraceResult(.unknownError,
                                        report: report,
                                        submissionDisposition: .retryable),
                attempted: false,
                isDurable: false)
        }
        defer { endSubmission() }

        do {
            guard try claimIfNeeded(report, origin: origin) else {
                return BacktraceSubmissionReceipt(
                    result: BacktraceResult(.unknownError,
                                            report: report,
                                            submissionDisposition: .retryable),
                    attempted: false,
                    isDurable: true)
            }
        } catch {
            BacktraceLogger.error("Unable to claim report \(report.identifier) for submission")
            return BacktraceSubmissionReceipt(
                result: BacktraceResult(error.backtraceStatus,
                                        report: report,
                                        submissionDisposition: error.backtraceSubmissionDisposition),
                attempted: false,
                isDurable: false)
        }

        var durable = false
        do {
            let result = try api.send(report) { [self] outcome in
                beforeFinalization?(outcome)
                durable = finalize(outcome, persistedReport: report, origin: origin)
            }
            return BacktraceSubmissionReceipt(result: result,
                                              attempted: true,
                                              isDurable: durable)
        } catch {
            // BacktraceApi always presents a classified failure to the finalizer before it throws,
            // `durable` already reflects rollback or persistence.
            return BacktraceSubmissionReceipt(
                result: BacktraceResult(error.backtraceStatus,
                                        report: report,
                                        submissionDisposition: error.backtraceSubmissionDisposition),
                attempted: true,
                isDurable: durable)
        }
    }

    /// Stops admission before transport cancellation begins.
    internal func prepareForShutdown() {
        lifecycleLock.lock()
        lifecycleState = .quiescing
        lifecycleLock.unlock()
    }

    /// Called after `BacktraceApi.shutdown()` has cancelled unfinished URLSession tasks.
    /// Repository shutdown is deferred until every response/cancellation has finalized locally.
    internal func finishShutdown(whenQuiesced completion: @escaping () -> Void) {
        lifecycleLock.lock()
        transportCancellationStarted = true
        if activeSubmissions == 0 {
            lifecycleLock.unlock()
            completion()
            return
        }
        quiescenceCompletions.append(completion)
        lifecycleLock.unlock()
    }

    private func beginSubmission() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard lifecycleState == .active else { return false }
        activeSubmissions += 1
        return true
    }

    private func endSubmission() {
        lifecycleLock.lock()
        activeSubmissions -= 1
        guard activeSubmissions == 0, transportCancellationStarted else {
            lifecycleLock.unlock()
            return
        }
        let completions = quiescenceCompletions
        quiescenceCompletions.removeAll()
        lifecycleLock.unlock()
        completions.forEach { $0() }
    }

    private func claimIfNeeded(_ report: BacktraceReport,
                               origin: BacktraceSubmissionOrigin) throws -> Bool {
        switch origin {
        case .pendingNativeCrash:
            return try repository.claimInitialSubmission(report)
        case .repositoryRetry:
            return try repository.claimRetrySubmission(report)
        case .live, .outOfMemory:
            return true
        }
    }

    private func finalize(_ outcome: BacktraceSubmissionOutcome,
                          persistedReport: BacktraceReport,
                          origin: BacktraceSubmissionOrigin) -> Bool {
        switch origin {
        case .pendingNativeCrash, .repositoryRetry:
            return finalizePersisted(outcome,
                                     persistedReport: persistedReport,
                                     origin: origin)
        case .live, .outOfMemory:
            return finalizeUnpersisted(outcome, origin: origin)
        }
    }

    private func finalizePersisted(_ outcome: BacktraceSubmissionOutcome,
                                   persistedReport: BacktraceReport,
                                   origin: BacktraceSubmissionOrigin) -> Bool {
        let disposition: BacktraceSubmissionDisposition
        let cancelled: Bool

        switch outcome {
        case .result(let result):
            disposition = result.submissionDisposition
            cancelled = false
        case .failure(let error, _):
            disposition = error.backtraceSubmissionDisposition
            cancelled = error.isBacktraceCancellation && isQuiescing
        }

        do {
            if cancelled {
                switch origin {
                case .pendingNativeCrash:
                    try repository.markReadyForInitialSubmission(persistedReport)
                case .repositoryRetry:
                    try repository.markReadyForRetry(persistedReport)
                case .live, .outOfMemory:
                    break
                }
                return true
            }

            switch disposition {
            case .accepted, .permanentFailure:
                return finishTerminalReport(persistedReport)
            case .rateLimited:
                try repository.markReadyForRetry(persistedReport)
                return true
            case .retryable:
                if origin == .repositoryRetry {
                    try repository.markReadyForRetry(
                        persistedReport,
                        incrementRetryCountWithLimit: retryLimit
                    )
                } else {
                    try repository.markReadyForRetry(persistedReport)
                }
                return true
            }
        } catch {
            BacktraceLogger.error("Unable to finalize delivery state for report \(persistedReport.identifier)")
            return false
        }
    }

    private func finalizeUnpersisted(_ outcome: BacktraceSubmissionOutcome,
                                     origin: BacktraceSubmissionOrigin) -> Bool {
        let report: BacktraceReport
        let disposition: BacktraceSubmissionDisposition

        switch outcome {
        case .result(let result):
            guard let submittedReport = result.report else { return false }
            report = submittedReport
            disposition = result.submissionDisposition
        case .failure(let error, let failedReport):
            report = failedReport
            disposition = error.backtraceSubmissionDisposition
        }

        switch disposition {
        case .accepted, .permanentFailure:
            return true
        case .rateLimited, .retryable:
            do {
                try repository.save(report, origin: persistedOrigin(for: origin))
                return true
            } catch {
                BacktraceLogger.error("Unable to persist report \(report.identifier) for retry")
                return false
            }
        }
    }

    private func persistedOrigin(for origin: BacktraceSubmissionOrigin) -> PersistedReportOrigin {
        switch origin {
        case .outOfMemory:
            return .outOfMemory
        case .pendingNativeCrash:
            return .nativeCrash
        case .live, .repositoryRetry:
            return .live
        }
    }

    private func finishTerminalReport(_ report: BacktraceReport) -> Bool {
        do {
            try repository.markTerminalForDeletion(report)
        } catch {
            BacktraceLogger.error("Unable to persist terminal state for report \(report.identifier)")
            do {
                try repository.delete(report)
                return true
            } catch {
                BacktraceLogger.error("Unable to remove terminal report \(report.identifier)")
                return false
            }
        }

        do {
            try repository.delete(report)
        } catch {
            // The durable terminal state suppresses replay; physical cleanup can be retried.
            BacktraceLogger.warning("Deferred cleanup of terminal report \(report.identifier)")
        }
        return true
    }
}
