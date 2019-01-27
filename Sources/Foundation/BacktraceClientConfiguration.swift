import Foundation

/// Backtrace client configuration settings.
@objc public class BacktraceClientConfiguration: NSObject {
    
    /// Client's credentials.
    @objc public let credentials: BacktraceCredentials
    
    /// Database settings
    @objc public let dbSettings: BacktraceDatabaseSettings
    
    /// Produces Backtrace client configuration settings.
    /// - Parameters:
    ///   - credentials: Backtrace server API credentials.
    ///   - dbSettings: Backtrace database settings
    @objc public init(credentials: BacktraceCredentials,
                      dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings()) {
        self.credentials = credentials
        self.dbSettings = dbSettings
    }
}
