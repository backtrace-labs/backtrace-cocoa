import Foundation

/// Backtrace client configuration settings.
@objc public class BacktraceClientConfiguration: NSObject {
    
    /// Client's credentials.
    @objc public let credentials: BacktraceCredentials
    
    /// Produces Backtrace client configuration settings.
    ///
    /// - Parameter credentials: Backtrace server API credentials.
    @objc public init(credentials: BacktraceCredentials) {
        self.credentials = credentials
    }
}
