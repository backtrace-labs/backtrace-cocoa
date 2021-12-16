import Foundation

/// Backtrace result containing the status and message.
@objc open class BacktraceResult: NSObject {

    /// Backtrace message.
    @objc public var message: String

    /// Report.
    @objc public var report: BacktraceReport?

    /// Result status.
    @objc public var backtraceStatus: BacktraceReportStatus

    init(_ status: BacktraceReportStatus, report: BacktraceReport? = nil, message: String? = nil) {
        self.message = message ?? status.description
        self.backtraceStatus = status
        self.report = report
        super.init()
    }
}

extension BacktraceResult {

    /// Description of `BacktraceResult`
    override open var description: String {
        return message
    }
}
