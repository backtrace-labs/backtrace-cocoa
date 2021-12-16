import Foundation

/// Backtrace error-free metrics settings
@objc public class BacktraceMetricsSettings: NSObject {

    /// Max events count, will attempt to submit metrics when this limit is reached
    @objc public var maxEventsCount: Int = 350

    /// Time interval in seconds between sending metrics reports. `0` disables auto-send of metrics
    /// Default: 30 minutes (1800 seconds)
    @objc public var timeInterval: Int = 1800

    /// Time interval in seconds between retries of sending metrics reports. Some backoff and fuzzing is applied.
    /// Default: 10 seconds
    @objc public var retryInterval: Int = 10

    /// Maximum number of retries. Default `3`.
    @objc public var retryLimit: Int = 3

    /// Custom submission URL. If null or empty will use default Backtrace metrics submission URL.
    @objc public var customSubmissionUrl: String = ""
}
