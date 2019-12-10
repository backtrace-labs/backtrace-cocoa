import Foundation

/// Backtrace client configuration settings.
@objc public class BacktraceClientConfiguration: NSObject {
    
    /// Client's credentials. To learn more about credentials, see
    /// https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    /// and https://help.backtrace.io/troubleshooting/what-is-a-submission-token .
    @objc public let credentials: BacktraceCredentials
    
    /// Database settings
    @objc public var dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings()
    
    /// Number of records sent in 1 minute. Default `3`.
    @objc public var reportsPerMin: Int = 3
    
    /// Flag indicating if the Backtrace client should report reports when the debugger is attached. Default `false`.
    @objc public var allowsAttachingDebugger: Bool = false
    
    /// Produces Backtrace client configuration settings.
    ///
    /// - Parameters:
    ///   - credentials: Backtrace server API credentials.
    @objc public init(credentials: BacktraceCredentials) {
        self.credentials = credentials
    }
    
    /// Produces Backtrace client configuration settings.
    ///
    /// - Parameters:
    ///   - credentials: Backtrace server API credentials.
    ///   - dbSettings: Backtrace database settings.
    ///   - reportsPerMin: Maximum number of records sent to Backtrace services in 1 minute. Default: `3`.
    ///   - allowsAttachingDebugger: if set to `true` BacktraceClient will report reports even when the debugger
    /// is attached. Default: `false`.
    @objc public init(credentials: BacktraceCredentials,
                      dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings(),
                      reportsPerMin: Int = 3,
                      allowsAttachingDebugger: Bool = false) {
        self.credentials = credentials
        self.dbSettings = dbSettings
        self.reportsPerMin = reportsPerMin
        self.allowsAttachingDebugger = allowsAttachingDebugger
    }
}
