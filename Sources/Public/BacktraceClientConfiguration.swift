import Foundation

/// Determines how the SDK should handle OOM (Out‑Of‑Memory) events.
@objc public enum BacktraceOomMode: Int {
    /// Disable OOM tracking (identical to legacy `detectOOM = false`).
    case none = 0
    /// Lightweight report (no symbolication, current thread).
    case light = 1
    /// Full crash report (all threads, symbolicated) – legacy default.
    case full = 2
}

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

#if os(iOS) && !targetEnvironment(macCatalyst)
    /// Breadcrumbs settings.
    @objc public var breadcrumbSettings: BacktraceBreadcrumbSettings = BacktraceBreadcrumbSettings()
#endif

    /// Number of records sent in 1 minute. Default `30`.
    @objc public var reportsPerMin: Int = 30

    /// Flag indicating if the Backtrace client should report reports when the debugger is attached. Default `false`.
    @objc public var allowsAttachingDebugger: Bool = false
    
    /// How the SDK should handle OOM detection.
    /// Default is `.none` to preserve launch‑time performance unless the integrator opts‑in.
    @objc public var oomMode: BacktraceOomMode = .none

    /// The legacy `detectOom` boolean remains for source compatibility but is now deprecated.
    @available(*, deprecated, renamed: "oomMode")
    @objc public var detectOom: Bool {
        get { oomMode != .none }
        set { oomMode = newValue ? .full : .none }
    }
    
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
    ///   - allowsAttachingDebugger: if set to `true` BacktraceClient will report reports even when the debugger is attached. Default: `false`.
    ///   - oomMode: BacktraceOomMode [.none, .light, .full]
    @objc public init(credentials: BacktraceCredentials,
                      dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings(),
                      reportsPerMin: Int = 30,
                      allowsAttachingDebugger: Bool = false,
                      oomMode: BacktraceOomMode = .none) {
        self.credentials = credentials
        self.dbSettings = dbSettings
        self.reportsPerMin = reportsPerMin
        self.allowsAttachingDebugger = allowsAttachingDebugger
        self.oomMode  = oomMode
    }
    
    /// Legacy Initialiser for compatibility.
    /// Produces Backtrace client configuration settings.
    ///
    /// - Parameters:
    ///   - credentials: Backtrace server API credentials.
    ///   - dbSettings: Backtrace database settings.
    ///   - reportsPerMin: Maximum number of records sent to Backtrace services in 1 minute. Default: `30`.
    ///   - allowsAttachingDebugger: if set to `true` BacktraceClient will report reports even when the debugger is attached. Default: `false`.
    ///   - detectOOM: if set to `true` BacktraceClient will detect when the app is out of memory. Default: `false`.
    @available(*, deprecated, message: "Use init(credentials:dbSettings:reportsPerMin:allowsAttachingDebugger:oomMode:) instead")
    @objc public convenience init(credentials: BacktraceCredentials,
                                  dbSettings: BacktraceDatabaseSettings = .init(),
                                  reportsPerMin: Int = 30,
                                  allowsAttachingDebugger: Bool = false,
                                  detectOOM: Bool = false) {
        self.init(credentials: credentials,
                  dbSettings: dbSettings,
                  reportsPerMin: reportsPerMin,
                  allowsAttachingDebugger: allowsAttachingDebugger,
                  oomMode: detectOOM ? .full : .none)
    }
}
