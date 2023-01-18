import Foundation

/// Provides the default implementation of `BacktraceClientProtocol` protocol.
@objc open class BacktraceClient: NSObject {

    enum WorkingMode {
        case normal
        case safe
    }

    /// Shared instance of BacktraceClient class. Should be created before sending any reports.
    @objc public static var shared: BacktraceClientProtocol?

    /// `BacktraceClient`'s configuration. Allows to configure `BacktraceClient` in a custom way.
    @objc public let configuration: BacktraceClientConfiguration

    /// Error-free metrics class instance
    @objc private let metricsInstance: BacktraceMetrics

#if os(iOS) || os(OSX)
    /// Breadcrumbs class instance
    @objc private let breadcrumbsInstance: BacktraceBreadcrumbs = BacktraceBreadcrumbs()
#endif

    private static var workingMode = WorkingMode.normal

    private let reporter: BacktraceReporter
    private let dispatcher: Dispatching
    private let reportingPolicy: ReportingPolicy

    private static var crashLoopDetector: BacktraceCrashLoopDetector?

    /// Initialize `BacktraceClient` with credentials. To learn more about credentials, see
    /// https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    /// and https://help.backtrace.io/troubleshooting/what-is-a-submission-token .
    ///
    /// - Parameter credentials: Credentials to register in Backtrace services.
    /// - Parameter crashReporter: Instance of the crash reporter to inject.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(credentials: BacktraceCredentials,
                                  crashReporter: BacktraceCrashReporter = BacktraceCrashReporter()) throws {
        try self.init(configuration: BacktraceClientConfiguration(credentials: credentials), crashReporter: crashReporter)
    }

    /// Initialize `BacktraceClient` with credentials. To learn more about credentials, see
    /// https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    /// and https://help.backtrace.io/troubleshooting/what-is-a-submission-token .
    ///
    /// - Parameter credentials: Credentials to register in Backtrace services.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(credentials: BacktraceCredentials) throws {
        try self.init(configuration: BacktraceClientConfiguration(credentials: credentials),
                      crashReporter: BacktraceCrashReporter())
    }

    /// Initialize `BacktraceClient` with `BacktraceClientConfiguration` instance. Allows to configure `BacktraceClient`
    /// in a custom way.
    ///
    /// - Parameter configuration: `BacktraceClient`s configuration.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(configuration: BacktraceClientConfiguration) throws {
        let api = BacktraceApi(credentials: configuration.credentials,
                               reportsPerMin: configuration.reportsPerMin)
        let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(), api: api, dbSettings: configuration.dbSettings,
                                             credentials: configuration.credentials)
        try self.init(configuration: configuration, debugger: DebuggerChecker.self, reporter: reporter,
                      dispatcher: Dispatcher(), api: api)
    }

    /// Initialize `BacktraceClient` with `BacktraceClientConfiguration` instance. Allows to configure `BacktraceClient`
    /// in a custom way.
    ///
    /// - Parameter configuration: `BacktraceClient`s configuration.
    /// - Parameter crashReporter: Instance of the crash reporter to inject.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(configuration: BacktraceClientConfiguration, crashReporter: BacktraceCrashReporter) throws {
        let api = BacktraceApi(credentials: configuration.credentials,
                               reportsPerMin: configuration.reportsPerMin)
        let reporter = try BacktraceReporter(reporter: crashReporter, api: api, dbSettings: configuration.dbSettings,
                                             credentials: configuration.credentials)

        try self.init(configuration: configuration, debugger: DebuggerChecker.self, reporter: reporter,
                      dispatcher: Dispatcher(), api: api)
    }

    init(configuration: BacktraceClientConfiguration, debugger: DebuggerChecking.Type = DebuggerChecker.self,
         reporter: BacktraceReporter, dispatcher: Dispatching = Dispatcher(),
         api: BacktraceApi) throws {

        self.dispatcher = dispatcher
        self.reporter = reporter
        self.configuration = configuration
        self.reportingPolicy = ReportingPolicy(configuration: configuration, debuggerChecker: debugger)
        self.metricsInstance = BacktraceMetrics(api: api)

        super.init()
                
        try startCrashReporter()
    }
}

// MARK: - BacktraceClient Safe Mode public API (crash loop detection)
extension BacktraceClient {
    
    @objc public static func enableSafeMode() {
        workingMode = .safe
        
        // Do any additional setup here - f.e. turn off reporting etc
    }
    
    @objc public static func disableSafeMode() {
        workingMode = .normal
        
        // Do any additional setup here - f.e. turn on reporting etc
    }
    
    @objc public static func isInSafeMode() -> Bool {
        return workingMode == .safe
    }
    
    @objc public static func enableCrashLoopDetection(_ threshold: Int = 0) {
        BacktraceCrashLoopCounter.start()

        crashLoopDetector = BacktraceCrashLoopDetector()
        crashLoopDetector?.updateThreshold(threshold)
    }
    
    @objc public static func disableCrashLoopDetection() {
        crashLoopDetector = nil
    }
    
    @objc public static func resetCrashLoopDetection() {
        BacktraceCrashLoopCounter.reset()
        crashLoopDetector?.clearStartupEvents()
    }
    
    @objc public static func isSafeModeRequired() -> Bool {
        let isInCrashLoop = crashLoopDetector?.detectCrashloop() ?? false
        if isInCrashLoop { enableSafeMode() }
        return isInCrashLoop
    }
    
    @objc public static func consecutiveCrashesCount() -> Int {
        return crashLoopDetector?.consecutiveCrashesCount ?? 0
    }
    
    // Added for testing without debugging purposes
    @objc public static func crashLoopEventsDatabase() -> String {
        return crashLoopDetector?.databaseDescription() ?? "Not enabled"
    }
}

// MARK: - BacktraceClientProviding
extension BacktraceClient: BacktraceClientCustomizing {

    /// The object that acts as the delegate object of the `BacktraceClient`.
    @objc public var delegate: BacktraceClientDelegate? {
        get {
            return reporter.delegate
        } set {
            reporter.delegate = newValue
        }
    }

    /// Additional attributes which are automatically added to each report.
    @objc public var attributes: Attributes {
        get {
            return reporter.attributes
        } set {
            reporter.attributes = newValue
        }
    }

    /// Additional file attachments which are automatically added to each report.
    @objc public var attachments: Attachments {
        get {
            return reporter.attachments
        } set {
            reporter.attachments = newValue
        }
    }
}

// MARK: - BacktraceReporting
extension BacktraceClient: BacktraceReporting {

    @objc public func send(error: Error,
                           attachmentPaths: [String] = [],
                           completion: @escaping ((BacktraceResult) -> Void)) {
        reportCrash(faultMessage: error.localizedDescription, attachmentPaths: attachmentPaths, completion: completion)
    }

    @objc public func send(message: String,
                           attachmentPaths: [String] = [],
                           completion: @escaping ((BacktraceResult) -> Void)) {
        reportCrash(faultMessage: message, attachmentPaths: attachmentPaths, completion: completion)
    }

    @objc public func send(exception: NSException?,
                           attachmentPaths: [String] = [],
                           completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        reportCrash(faultMessage: exception?.name.rawValue ?? "Unknown exception", exception: exception,
                    attachmentPaths: attachmentPaths, completion: completion)
    }

    @objc public func send(attachmentPaths: [String] = [],
                           completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        reportCrash(attachmentPaths: attachmentPaths, completion: completion)
    }

    private func reportCrash(faultMessage: String? = nil, exception: NSException? = nil, attachmentPaths: [String] = [],
                             completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        guard reportingPolicy.allowsReporting else {
            completion(BacktraceResult(.debuggerAttached))
            return
        }

        guard let resource = try? reporter.generate(exception: exception,
                                                    attachmentPaths: attachmentPaths,
                                                    faultMessage: faultMessage) else {
            completion(BacktraceResult(.unknownError))
            return
        }

        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            completion(self.reporter.send(resource: resource))
        }, completion: {
            BacktraceLogger.debug("Finished sending an error report.")
        })
    }

    func startCrashReporter() throws {
        guard reportingPolicy.allowsReporting else {
            return
        }

        try reporter.enableCrashReporter()
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                try self.reporter.handlePendingCrashes()
            } catch {
                BacktraceLogger.error(error)
            }
            }, completion: {
                BacktraceLogger.debug("Started error reporter.")
        })

        if self.configuration.detectOom {
            dispatcher.dispatch({ [weak self] in
                guard let self = self else { return }
                self.reporter.enableOomWatcher()
                }, completion: {
                    BacktraceLogger.debug("Started OOM Watcher.")
            })
        }
    }
}

// MARK: - BacktraceLogging
extension BacktraceClient: BacktraceLogging {

    /// A collection of logging destinations.
    public var loggingDestinations: Set<BacktraceBaseDestination> {
        get {
            return BacktraceLogger.destinations
        }
        set {
            BacktraceLogger.destinations = newValue
        }
    }
}

// MARK: - BacktraceMetricsProtocol
extension BacktraceClient: BacktraceMetricsProtocol {
    /// Error-free metrics class instance
    @objc public var metrics: BacktraceMetrics {
        return self.metricsInstance
    }
}

// MARK: - BacktraceBreadcrumbProtocol
#if os(iOS) || os(OSX)
extension BacktraceClient: BacktraceBreadcrumbProtocol {
    @objc public var breadcrumbs: BacktraceBreadcrumbs {
        return self.breadcrumbsInstance
    }

    @objc public func enableBreadcrumbs() {
        breadcrumbsInstance.enableBreadcrumbs()
    }

    @objc public func enableBreadcrumbs(_ breadcrumbSettings: BacktraceBreadcrumbSettings) {
        breadcrumbsInstance.enableBreadcrumbs(breadcrumbSettings)
    }

    @objc public func addBreadcrumb(_ message: String,
                                    attributes: [String: String],
                                    type: BacktraceBreadcrumbType,
                                    level: BacktraceBreadcrumbLevel) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, attributes: attributes, type: type, level: level)
    }

    @objc public func addBreadcrumb(_ message: String) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message)
    }

    @objc public func addBreadcrumb(_ message: String, attributes: [String: String]) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, attributes: attributes)
    }

    @objc public func addBreadcrumb(_ message: String, type: BacktraceBreadcrumbType, level: BacktraceBreadcrumbLevel) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, type: type, level: level)
    }

    @objc public func addBreadcrumb(_ message: String, level: BacktraceBreadcrumbLevel) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, level: level)
    }

    @objc public func addBreadcrumb(_ message: String, type: BacktraceBreadcrumbType) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, type: type)
    }

    @objc public func clearBreadcrumbs() -> Bool {
        return breadcrumbsInstance.clear()
    }
}
#endif
