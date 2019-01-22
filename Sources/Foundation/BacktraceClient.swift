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
    ///   - completion: Bactrace services response.
    @objc func send(completion: @escaping ((_ result: BacktraceResult) -> Void))
    
    /// Automatically generates and sends a crash report to Backtrace services.
    @objc func send()
}

/// Provides the default implementation of BacktraceClientProviding protocol.
@objc public class BacktraceClient: NSObject {

    /// Shared instance of BacktraceClient class.
    @objc public static let shared = BacktraceClient()
    private var client: BacktraceClientType
    private let dispatcher: Dispatcher

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
                                                   token: configuration.credentials.token)
        client = BacktraceRegisteredClient(networkClient: networkClient)
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                try self.client.handlePendingCrashes()
            } catch {
                BacktraceLogger.error(error)
            }
            }, completion: {
                BacktraceLogger.debug("Finished")
        })
    }
    
    /// Automatically generates and sends a crash report to Backtrace services.
    @objc public func send() {
        send(completion: { _ in })
    }
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - completion: Bactrace services response.
    @objc public func send(completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                completion(try self.client.send())
            } catch let responseError as BacktraceErrorResponse {
                completion(responseError.backtraceResult)
            } catch {
                BacktraceLogger.error(error)
                completion(BacktraceResult(.serverError))
            }
            }, completion: {
                BacktraceLogger.debug("Finished")
        })
    }
}
