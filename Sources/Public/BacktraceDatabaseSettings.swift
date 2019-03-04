import Foundation

/// Backtrace local database settings.
@objc public class BacktraceDatabaseSettings: NSObject {
    
    /// Max record count stored in database. `0` means "no limit". Default `0`.
    @objc public var maxRecordCount: Int = 0
    
    /// Maximum database size in MB. If value is equal to zero, then size is unlimied.
    @objc public var maxDatabaseSize: Int = 0
    
    /// How much seconds library should wait before next retry.
    @objc public var retryInterval: Int = 5
    
    /// Maximum number of retries.
    @objc public var retryLimit: Int = 3
    
    /// Retry behaviour.
    @objc public var retryBehaviour: RetryBehaviour = .interval
    
    /// Retry order.
    @objc public var retryOrder: RetryOder = .queue
    
    internal var maxDatabaseSizeInBytes: Int {
        return maxDatabaseSize * 1024 * 1024
    }
    
    static let unlimited: Int = 0
}

/// Backtrace retrying behaviour for not successfully sent crashes.
@objc public enum RetryBehaviour: Int {
    case none
    case interval
}

/// Backtrace retrying order of not successfully sent crashes.
@objc public enum RetryOder: Int {
    case queue
    case stack
}
