import Foundation

/// Backtrace server API credentials.
@objc public class BacktraceCredentials: NSObject {
    let endpoint: URL
    let token: String
    
    /// Produces Backtrace server API credentials.
    ///
    /// - Parameters:
    ///   - endpoint: Endpoint to Backtrace services,
    ///   - token: Access token to Backtrace services,
    /// - Throws: Error thrown when passes invalid URL.
    @objc public init(endpoint: URL, token: String) {
        self.token = token
        self.endpoint = endpoint
    }
}