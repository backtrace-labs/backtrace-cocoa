import Foundation

/// Provides the default implementation of BacktraceClientProviding protocol.
@objc open class BacktraceClient: NSObject {
    
    /// Shared instance of BacktraceClient class.
    @objc public static var shared: BacktraceClientProtocol?
    @objc public let configuration: BacktraceClientConfiguration
    
    private let reporter: BacktraceReporter
    private let dispatcher: Dispatching
    private let reportingPolicy: ReportingPolicy
    
    @objc public convenience init(credentials: BacktraceCredentials) throws {
        try self.init(configuration: BacktraceClientConfiguration(credentials: credentials))
    }
    
    @objc public convenience init(configuration: BacktraceClientConfiguration) throws {
        let api = BacktraceApi(endpoint: configuration.credentials.endpoint,
                               token: configuration.credentials.token,
                               reportsPerMin: configuration.reportsPerMin)
        let reporter = try BacktraceReporter(reporter: CrashReporter(), api: api, dbSettings: configuration.dbSettings,
                                             reportsPerMin: configuration.reportsPerMin)
        try self.init(configuration: configuration, debugger: DebuggerChecker.self, reporter: reporter,
                      dispatcher: Dispatcher(), api: api)
    }
    
    init(configuration: BacktraceClientConfiguration, debugger: DebuggerChecking.Type = DebuggerChecker.self,
         reporter: BacktraceReporter, dispatcher: Dispatching = Dispatcher(), api: BacktraceApiProtocol) throws {
        
        self.dispatcher = dispatcher
        self.reporter = reporter
        self.configuration = configuration
        self.reportingPolicy = ReportingPolicy(configuration: configuration, debuggerChecker: debugger)
        
        super.init()
        try startCrashReporter()
    }
}

// MARK: - BacktraceClientProviding
extension BacktraceClient: BacktraceClientCustomizing {
    /// BacktraceClientDelegate. Subscribe to receive all the events.
    @objc public weak var delegate: BacktraceClientDelegate? {
        set {
            reporter.delegate = newValue
        } get {
            return reporter.delegate
        }
    }
    
    @objc public var userAttributes: Attributes {
        get {
            return reporter.userAttributes
        }
        set {
            reporter.userAttributes = newValue
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
        
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                completion(try self.reporter.send(exception: exception, attachmentPaths: attachmentPaths,
                                                  faultMessage: faultMessage))
            } catch {
                BacktraceLogger.error(error)
                completion(BacktraceResult(.unknownError))
            }
            }, completion: {
                BacktraceLogger.debug("Finished")
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
                BacktraceLogger.debug("Finished")
        })
    }
}

// MARK: - BacktraceLogging
extension BacktraceClient: BacktraceLogging {
    public var destinations: Set<BacktraceBaseDestination> {
        get {
            return BacktraceLogger.destinations
        }
        set {
            BacktraceLogger.destinations = newValue
        }
    }
}
