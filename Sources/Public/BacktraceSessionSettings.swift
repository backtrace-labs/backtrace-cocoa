import Foundation

/// Configuration for session recording, feedback, and log capture features.
///
/// Set on `BacktraceClientConfiguration.sessionSettings` before initializing `BacktraceClient`.
/// Pass `nil` (the default) to disable all session features with zero overhead.
@objc public class BacktraceSessionSettings: NSObject {

    // MARK: - Authentication

    /// TestFairy app token for session API calls.
    /// Required for session features to function.
    @objc public var appToken: String?

    // MARK: - Network

    /// Collector endpoint URL for session data.
    /// Defaults to `https://api2.testfairy.com/services/` (TF collector).
    /// Set a custom URL for on-premise or future Backtrace-native collector.
    @objc public var collectorURL: URL?

    // MARK: - Encryption

    /// RSA public key in PEM or DER (Base64) format for end-to-end encryption.
    /// When set, screenshots, logs, and feedback are encrypted before upload.
    /// Pass `nil` to disable encryption.
    @objc public var encryptionPublicKey: String?

    // MARK: - Screenshots (iOS only)

    /// Interval between automatic screenshot captures, in seconds.
    /// Set to `0` to disable periodic screenshots. Default `5.0`.
    @objc public var screenshotInterval: TimeInterval = 5.0

    /// JPEG compression quality for screenshots. Default `.medium`.
    @objc public var screenshotQuality: BacktraceScreenshotQuality = .medium

    // MARK: - Feedback (iOS only)

    /// Enable shake-to-report gesture. Default `true`.
    /// When `false`, feedback can still be triggered programmatically via `showFeedbackForm()`.
    @objc public var shakeToReport: Bool = true

    /// Customization for the feedback form UI.
    /// Pass `nil` to use the default form (optional email + required description).
    @objc public var feedbackOptions: BacktraceFeedbackOptions?

    // MARK: - Logging

    /// Minimum log level to capture. Messages below this level are ignored. Default `.verbose`.
    @objc public var logLevel: BacktraceSessionLogLevel = .verbose

    /// Capture `stderr`/`stdout` output (NSLog, print, os_log).
    /// **Opt-in** — may interfere with Xcode console and other SDKs. Default `false`.
    @objc public var captureConsoleOutput: Bool = false

    // MARK: - Event Buffering

    /// Maximum number of events buffered in memory before auto-flush. Default `64`.
    @objc public var eventBufferSize: Int = 64

    /// Maximum interval between event flushes, in seconds. Default `15.0`.
    @objc public var eventFlushInterval: TimeInterval = 15.0

    // MARK: - Offline Storage

    /// Maximum offline storage for pending uploads, in megabytes. Default `50`.
    @objc public var maxOfflineStorageMB: Int = 50

    /// Interval between offline retry attempts, in seconds. Default `30.0`.
    @objc public var offlineRetryInterval: TimeInterval = 30.0

    // MARK: - Metrics

    /// Collect CPU usage metrics. Default `true`.
    @objc public var collectCPU: Bool = true

    /// Collect memory usage metrics. Default `true`.
    @objc public var collectMemory: Bool = true

    /// Collect battery status metrics (iOS only). Default `true`.
    @objc public var collectBattery: Bool = true

    /// Interval between periodic metric samples, in seconds. Default `5.0`.
    @objc public var metricsInterval: TimeInterval = 5.0

    @objc public override init() {
        super.init()
    }
}
