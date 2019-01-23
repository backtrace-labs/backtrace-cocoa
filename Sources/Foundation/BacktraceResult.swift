import Foundation

/// Backtrace result containing the status and message.
@objc open class BacktraceResult: NSObject {
    
    /// Backtrace message.
    @objc public let message: String
    
    init(_ status: BacktraceResultStatus) {
        self.message = status.description
    }
    
    init(error: Error) {
        self.message = error.localizedDescription
    }
}

extension BacktraceResult {
    override open var description: String {
        return
            """
            Backtrace result:
            - message: \(message)
            """
    }
}
