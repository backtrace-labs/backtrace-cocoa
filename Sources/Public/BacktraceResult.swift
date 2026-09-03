import Foundation

enum BacktraceSubmissionDisposition: Equatable {
    case accepted
    case retryable
    case permanentFailure
    case rateLimited
}

/// Backtrace result containing the status and message.
@objc open class BacktraceResult: NSObject {

    /// Backtrace message.
    @objc public var message: String

    /// Report.
    @objc public var report: BacktraceReport?

    /// Result status.
    @objc public var backtraceStatus: BacktraceReportStatus

    /// Internal delivery policy used by initial sends and repository replay.
    let submissionDisposition: BacktraceSubmissionDisposition

    init(_ status: BacktraceReportStatus,
         report: BacktraceReport? = nil,
         message: String? = nil,
         submissionDisposition: BacktraceSubmissionDisposition? = nil) {
        self.message = message ?? status.description
        self.backtraceStatus = status
        self.report = report
        self.submissionDisposition = submissionDisposition ?? status.defaultSubmissionDisposition
        super.init()
    }
}

extension BacktraceResult {

    /// Description of `BacktraceResult`
    override open var description: String {
        return message
    }
}

private extension BacktraceReportStatus {
    var defaultSubmissionDisposition: BacktraceSubmissionDisposition {
        switch self {
        case .ok:
            return .accepted
        case .limitReached:
            return .rateLimited
        case .serverError, .unknownError:
            return .retryable
        case .debuggerAttached:
            return .permanentFailure
        }
    }
}
