import Foundation

/// Backtrace client configuration settings.
@objc public class BacktraceClientConfiguration: NSObject {
    
    /// Client's credentials.
    @objc public let credentials: BacktraceCredentials
    
    /// Database settings
    @objc public let dbSettings: BacktraceDatabaseSettings
    
    /// Number of records sent in 1 minute. Default: 3.
    @objc public let reportsPerMin: Int
    
    /// Produces Backtrace client configuration settings.
    /// - Parameters:
    ///   - credentials: Backtrace server API credentials.
    ///   - dbSettings: Backtrace database settings
    ///   - reportsPerMin: Maximum number of records sent to Backtrace services in 1 minute. Default: 3.
    @objc public init(credentials: BacktraceCredentials,
                      dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings(),
                      reportsPerMin: Int = 3) {
        self.credentials = credentials
        self.dbSettings = dbSettings
        self.reportsPerMin = reportsPerMin
    }
}
