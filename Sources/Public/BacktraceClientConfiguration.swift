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

#if os(iOS) && !targetEnvironment(macCatalyst)
    /// Breadcrumbs settings.
    @objc public var breadcrumbSettings: BacktraceBreadcrumbSettings = BacktraceBreadcrumbSettings()
#endif

    /// Number of records sent in 1 minute. Default `30`.
    @objc public var reportsPerMin: Int = 30

    /// Flag indicating if the Backtrace client should report reports when the debugger is attached. Default `false`.
    @objc public var allowsAttachingDebugger: Bool = false

    /// Flag responsible for detecting and sending possible OOM cashes
    @objc public var detectOom: Bool = false
    
    /// Custom directory for storing `.plcrash` files. Defaults to `nil`,
    /// Defaults to PLCrashReporter standard directory.
    @objc public var crashDirectory: URL?

    /// File protection for the custom directory. Defaults to `.none`.
    ///
    /// - Important: Using `.none` ensures the app can write crash reports
    ///   even if the device is locked. More secure options can cause missed crash logs.
    @objc public var fileProtection: FileProtectionType = .none
    
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
    
    /// Produces Backtrace client configuration settings, custom crash log directory and file protection level.
    ///
    /// - Parameters:
    ///   - credentials: Backtrace server API credentials.
    ///   - dbSettings: Backtrace database settings.
    ///   - reportsPerMin: Maximum number of records sent to Backtrace services in 1 minute. Default: `30`.
    ///   - allowsAttachingDebugger: if set to `true` BacktraceClient will report reports even when the debugger is attached. Default: `false`.
    ///   - detectOOM: if set to `true` BacktraceClient will detect when the app is out of memory. Default: `false`.
    ///   - crashDirectory: Custom directory for storing `.plcrash` files. Defaults to `nil`PLCrashReporter standard directory.
    ///   - fileProtection: OS file protection level. Default to`.none`to ensure the crash reports writes even if the device is locked. More secure options can cause missed crash logs.
    @objc public init(credentials: BacktraceCredentials,
                      dbSettings: BacktraceDatabaseSettings = BacktraceDatabaseSettings(),
                      reportsPerMin: Int = 30,
                      allowsAttachingDebugger: Bool = false,
                      detectOOM: Bool = false,
                      crashDirectory: URL? = nil,
                      fileProtection: FileProtectionType = .none) {

        self.credentials = credentials
        self.dbSettings = dbSettings
        self.reportsPerMin = reportsPerMin
        self.allowsAttachingDebugger = allowsAttachingDebugger
        self.detectOom = detectOOM
        self.crashDirectory = crashDirectory
        self.fileProtection = fileProtection
    }
}
