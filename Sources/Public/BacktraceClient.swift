import Foundation

/// Provides the default implementation of `BacktraceClientProtocol` protocol.
@objc open class BacktraceClient: NSObject {

    /// Shared instance of BacktraceClient class. Should be created before sending any reports.
    @objc public static var shared: BacktraceClientProtocol?

    /// `BacktraceClient`'s configuration. Allows to configure `BacktraceClient` in a custom way.
    @objc public let configuration: BacktraceClientConfiguration

    /// Error-free metrics class instance
    @objc public let metricsInstance: BacktraceMetrics

    private let reporter: BacktraceReporter
    private let dispatcher: Dispatching
    private let reportingPolicy: ReportingPolicy

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
        let metrics = BacktraceMetrics(api: api)
        try self.init(configuration: configuration, debugger: DebuggerChecker.self, reporter: reporter,
                      dispatcher: Dispatcher(), api: api, metrics: metrics)
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
        let metrics = BacktraceMetrics(api: api)
        try self.init(configuration: configuration, debugger: DebuggerChecker.self, reporter: reporter,
                      dispatcher: Dispatcher(), api: api, metrics: metrics)
    }

    init(configuration: BacktraceClientConfiguration, debugger: DebuggerChecking.Type = DebuggerChecker.self,
         reporter: BacktraceReporter, dispatcher: Dispatching = Dispatcher(),
         api: BacktraceApi, metrics: BacktraceMetrics) throws {

        self.dispatcher = dispatcher
        self.reporter = reporter
        self.configuration = configuration
        self.reportingPolicy = ReportingPolicy(configuration: configuration, debuggerChecker: debugger)
        self.metricsInstance = metrics

        super.init()
        try startCrashReporter()
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
                           attachmentPaths: [String],
                           completion: @escaping ((BacktraceResult) -> Void)) {
        reportCrash(faultMessage: error.localizedDescription, attachmentPaths: attachmentPaths, completion: completion)
    }

    @objc public func send(message: String,
                           attachmentPaths: [String],
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

        if self.configuration.detectOom {
            if #available(iOS 15.3.1, *) {
                BacktraceLogger.debug("Not enabling OomWatcher for iOS 15.3.1+")
            }else{
                self.reporter.enableOomWatcher()
            }
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
