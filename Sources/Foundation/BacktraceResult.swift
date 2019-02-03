import Foundation

/// Backtrace result containing the status and message.
@objc open class BacktraceResult: NSObject {
    
    /// Backtrace message.
    @objc public var message: String
    
    /// Report.
    @objc public var backtraceData: BacktraceCrashReport?
    
    /// Result status.
    @objc public var backtraceStatus: BacktraceResultStatus
    
    init(_ status: BacktraceResultStatus, message: String, backtraceReport: BacktraceCrashReport? = nil) {
        self.message = message
        self.backtraceStatus = status
        self.backtraceData = backtraceReport
        super.init()
    }
    
    class func serverError(_ message: String, backtraceReport: BacktraceCrashReport? = nil) -> BacktraceResult {
        return BacktraceResult(.serverError, message: message, backtraceReport: backtraceReport)
    }
    
    class func unknownError(_ backtraceResult: BacktraceResult? = nil) -> BacktraceResult {
        return BacktraceResult(.unknownError, message: "Unknown error",
                               backtraceReport: backtraceResult?.backtraceData)
    }
    
    class func limitReached(_ backtraceReport: BacktraceCrashReport? = nil) -> BacktraceResult {
        return BacktraceResult(.limitReached, message: "Limit reached.", backtraceReport: backtraceReport)
    }
}

extension BacktraceResult {
    override open var description: String {
        return
            """
            Backtrace result:
            - message: \(message)
            - status: \(backtraceStatus.description)
            """
    }
}
