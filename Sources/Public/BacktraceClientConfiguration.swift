import Foundation

/// Backtrace client configuration settings.
@objc public class BacktraceClientConfiguration: NSObject {

    /// Client's credentials. To learn more about credentials, see
    /// https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    /// and https://help.backtrace.io/troubleshooting/what-is-a-submission-token .
    @objc public let credentials: BacktraceCredentials

    /// Database settings.
    @objc public var dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings()

    /// Error-free metrics settings
    @objc public var metricsSettings: BacktraceMetricsSettings = BacktraceMetricsSettings()

    /// Number of records sent in 1 minute. Default `30`.
    @objc public var reportsPerMin: Int = 30

    /// Flag indicating if the Backtrace client should report reports when the debugger is attached. Default `false`.
    @objc public var allowsAttachingDebugger: Bool = false

    /// Flag responsible for detecting and sending possible OOM cashes
    @objc public var detectOom: Bool = false
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
    ///   - reportsPerMin: Maximum number of records sent to Backtrace services in 1 minute. Default: `30`.
    ///   - allowsAttachingDebugger: if set to `true` BacktraceClient will report reports even when the debugger
    /// is attached. Default: `false`.
    ///   - detectOOM: if set to `true` BacktraceClient will detect when the app is out of memory. Default: `false`.
    @objc public init(credentials: BacktraceCredentials,
                      dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings(),
                      reportsPerMin: Int = 30,
                      allowsAttachingDebugger: Bool = false,
                      detectOOM: Bool = false) {
        self.credentials = credentials
        self.dbSettings = dbSettings
        self.reportsPerMin = reportsPerMin
        self.allowsAttachingDebugger = allowsAttachingDebugger
        self.detectOom = detectOOM
    }
}
