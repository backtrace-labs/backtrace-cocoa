import Foundation

/// Backtrace result containing the status and message.
@objc open class BacktraceResult: NSObject {
    
    /// Backtrace result status.
    @objc public let status: BacktraceResultStatus
    
    /// Backtrace message.
    @objc public let message: String
    
    init(_ status: BacktraceResultStatus) {
        self.status = status
        self.message = status.messageDescription
    }
    
    init(status: BacktraceResultStatus, message: String) {
        self.status = status
        self.message = message
    }
}

extension BacktraceResult {
    override open var description: String {
        return
            """
            Backtrace result:
            - message: \(message)
            - status: \(status)
            """
    }
}
