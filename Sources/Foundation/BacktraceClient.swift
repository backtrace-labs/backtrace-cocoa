import Foundation

/// Public BacktraceClient protocol.
@objc public protocol BacktraceClientProviding {

    /// Registers to Backtrace services using provided credentials.
    ///
    /// - Parameter credentials: Backtrace API credentials.
    @objc func register(credentials: BacktraceCredentials)
    
    /// Registers to Backtrace services using custom client configuration.
    ///
    /// - Parameter configuration: Custom Backtrace client configuration.
    @objc func register(configuration: BacktraceClientConfiguration)
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - completion: Backtrace services response.
    @objc func send(completion: @escaping ((_ result: BacktraceResult) -> Void))
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - exception: instance of NSException,
    ///   - completion: Backtrace services response.
    @objc func send(exception: NSException, completion: @escaping ((_ result: BacktraceResult) -> Void))
}

/// Provides the default implementation of BacktraceClientProviding protocol.
@objc public class BacktraceClient: NSObject {

    /// Shared instance of BacktraceClient class.
    @objc public static let shared = BacktraceClient()
    
    /// BacktraceClientDelegate. Subscribe to receive all the events.
    @objc public weak var delegate: BacktraceClientDelegate? {
        set {
            networkClient?.delegate = newValue
        } get {
            return networkClient?.delegate
        }
    }
    private var client: BacktraceClientType
    private let dispatcher: Dispatcher
    private var networkClient: NetworkClientType?

    private override init() {
        self.client = BacktraceUnregisteredClient()
        self.dispatcher = Dispatcher()
        super.init()
    }
}

// MARK: - BacktraceClientProviding
extension BacktraceClient: BacktraceClientProviding {
    
    /// Registers to Backtrace services and then sends pending crashes.
    ///
    /// - Parameter credentials: Backtrace API credentials.
    @objc public func register(credentials: BacktraceCredentials) {
        register(configuration: BacktraceClientConfiguration(credentials: credentials))
    }
    
    /// Registers to Backtrace services with custom configuration sends pending crashses.
    ///
    /// - Parameter configuration: Custom Backtrace client configuration.
    @objc public func register(configuration: BacktraceClientConfiguration) {
        let networkClient = BacktraceNetworkClient(endpoint: configuration.credentials.endpoint,
                                                   token: configuration.credentials.token,
                                                   reportsPerMin: configuration.reportsPerMin)
        self.networkClient = networkClient
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                self.client = try BacktraceRegisteredClient(networkClient: networkClient,
                                                            dbSettings: configuration.dbSettings,
                                                            reportsPerMin: configuration.reportsPerMin)
                try self.client.handlePendingCrashes()
            } catch {
                BacktraceLogger.error(error)
            }
            }, completion: {
                BacktraceLogger.debug("Finished")
        })
    }
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - exception: instance of NSException,
    ///   - completion: Backtrace services response.
    @objc public func send(exception: NSException, completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        let defaultAttributes = DefaultAttributes.current()
        BacktraceLogger.debug("Default attributes: \(defaultAttributes)")
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                completion(try self.client.send(exception, defaultAttributes))
            } catch {
                BacktraceLogger.error(error)
                completion(BacktraceResult.unknownError())
            }
            }, completion: {
                BacktraceLogger.debug("Finished")
        })
    }
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - completion: Backtrace services response.
    @objc public func send(completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        let defaultAttributes = DefaultAttributes.current()
        BacktraceLogger.debug("Default attributes: \(defaultAttributes)")
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                completion(try self.client.send(nil, defaultAttributes))
            } catch {
                BacktraceLogger.error(error)
                completion(BacktraceResult.unknownError())
            }
            }, completion: {
                BacktraceLogger.debug("Finished")
        })
    }
}
