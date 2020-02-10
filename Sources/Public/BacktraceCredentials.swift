import Foundation

/// Backtrace server API credentials.
@objc public class BacktraceCredentials: NSObject {
    
    let configuration: Configuration
    
    enum Configuration {
        case submissionUrl(URL)
        case endpoint(URL, token: String)
    }
    /// Produces Backtrace server API credentials.
    ///
    /// - Parameters:
    ///   - endpoint: Endpoint to Backtrace services.
    ///   See more: https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    ///   - token: Access token to Backtrace service.
    ///   See more: https://help.backtrace.io/troubleshooting/what-is-a-submission-token
    @objc public init(endpoint: URL, token: String) {
        self.configuration = .endpoint(endpoint, token: token)
    }
    
    /// Produces Backtrace server API credentials.
    ///
    /// - Parameters:
    ///   - submissionUrl: The submission URL containing authentication credentials.
    @objc public init(submissionUrl: URL) {
        self.configuration = .submissionUrl(submissionUrl)
    }
}
