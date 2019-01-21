
import Foundation

/// Public BacktraceClient protocol.
@objc public protocol BacktraceClientProviding {

    /// Registers to Backtrace services using provided credentials.
    ///
    /// - Parameter credentials: Backtrace API credentials.
    @objc func register(credentials: BacktraceCredentials)
    
    /// Registers to Backtrace services using custom client configuration.
    ///
    /// - Parameter configuration: Custom Backtrace client configuration,
    @objc func register(configuration: BacktraceClientConfiguration)
    
    /// Sends a crash report to Backtrace services.
    ///
    /// - Parameters:
    ///   - error: catched error
    ///   - completion:
    @objc func send(_ error: Error, completion: ((_ result: BacktraceResult) -> Void)?)
    
    /// Sends a crash report to Backtrace services.
    ///
    /// - Parameters:
    ///   - exception: NSException
    ///   - completion:
    @objc func send(exception: NSException, completion: ((_ result: BacktraceResult) -> Void)?)
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
    @objc public func register(credentials: BacktraceCredentials) {
        register(configuration: BacktraceClientConfiguration(credentials: credentials))
    }
    
    @objc public func register(configuration: BacktraceClientConfiguration) {
        let networkClient = BacktraceNetworkClient(endpoint: configuration.credentials.endpoint,
                                                   token: configuration.credentials.token)
        client = BacktraceRegisteredClient(networkClient: networkClient)
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                try self.client.handlePendingCrashes()
            } catch {
                Logger.error(error)
            }
            }, completion: {
                Logger.debug("Finished")
        })
    }
    
    @objc public func send(exception: NSException, completion: ((BacktraceResult) -> Void)?) {
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                completion?(try self.client.send(exception: exception))
            } catch {
                Logger.error(error)
                completion?(BacktraceResult(.serverError))
            }
            }, completion: {
                Logger.debug("Finished")
        })
    }

    @objc public func send(_ error: Error, completion: ((_ result: BacktraceResult) -> Void)? = nil) {
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                completion?(try self.client.send(error))
            } catch {
                Logger.error(error)
                completion?(BacktraceResult(.serverError))
            }
            }, completion: {
                Logger.debug("Finished")
        })
    }
}
