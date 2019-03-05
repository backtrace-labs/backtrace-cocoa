import Foundation

/// Provides the default implementation of BacktraceClientProviding protocol.
@objc open class BacktraceClient: NSObject {
    
    /// Shared instance of BacktraceClient class.
    @objc public static var shared: BacktraceClientProtocol?
    
    private var reporter: BacktraceReporter
    private let dispatcher: Dispatcher
    
    @objc public convenience init(credentials: BacktraceCredentials) throws {
        try self.init(configuration: BacktraceClientConfiguration(credentials: credentials))
    }
    
    @objc public init(configuration: BacktraceClientConfiguration) throws {
        dispatcher = Dispatcher()
        let api = BacktraceApi(endpoint: configuration.credentials.endpoint,
                               token: configuration.credentials.token,
                               reportsPerMin: configuration.reportsPerMin)
        reporter = try BacktraceReporter(reporter: CrashReporter(), api: api,
                                         dbSettings: configuration.dbSettings,
                                         reportsPerMin: configuration.reportsPerMin)
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
    @objc public func send(exception: NSException?, completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                completion(try self.reporter.send(exception: exception))
            } catch {
                BacktraceLogger.error(error)
                completion(BacktraceResult.unknownError())
            }
            }, completion: {
                BacktraceLogger.debug("Finished")
        })
    }
    
    @objc public func send(completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        send(exception: nil, completion: completion)
    }
    
    func startCrashReporter() throws {
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
