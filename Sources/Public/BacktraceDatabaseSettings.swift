import Foundation

/// Backtrace local database settings.
@objc public class BacktraceDatabaseSettings: NSObject {

    /// Max record count stored in database. `0` means "no limit". Default `0`.
    @objc public var maxRecordCount: Int = 0

    /// Maximum database size in MB. If value is equal to zero, then size is unlimited. Default `0`.
    @objc public var maxDatabaseSize: Int = 0

    /// How much seconds library should wait before next retry. Default `5`.
    @objc public var retryInterval: Int = 5

    /// Maximum number of retries. Default `3`.
    @objc public var retryLimit: Int = 3

    /// Retry behaviour. Default `RetryBehaviour.interval`.
    @objc public var retryBehaviour: RetryBehaviour = .interval

    /// Retry order. Default `RetryOder.queue`.
    @objc public var retryOrder: RetryOrder = .queue

    /// Enable the hostname to be reported. This will cause the end-user to get the Local Network permissions pop-up.
    @objc public var reportHostName: Bool = false

    internal var maxDatabaseSizeInBytes: Int {
        return maxDatabaseSize * 1024 * 1024
    }

    static let unlimited: Int = 0
}

/// Backtrace retrying behaviour for not successfully sent reports.
@objc public enum RetryBehaviour: Int {
    /// Library will not retry sending report.
    case none
    /// Library will retry sending report with interval specified in `BacktraceDatabaseSettings.retryInterval` property.
    case interval
}

/// Backtrace retrying order for not successfully sent reports.
@objc public enum RetryOrder: Int {
    /// Library will retry sending oldest reports first (FIFO).
    case queue
    /// Library will retry sending youngest reports first (LIFO).
    case stack
}
