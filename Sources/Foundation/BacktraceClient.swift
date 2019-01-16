//
//  BacktraceClient.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 08/12/2018.
//

import Foundation

/// Public BacktraceClient protocol.
@objc public protocol BacktraceClientProviding {

    /// Register to Backtrace services.
    ///
    /// - Parameters:
    ///   - endpoint: Backtrace API endpoint
    ///   - token: Backtrace API token
    @objc func register(endpoint: String, token: String)
    
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
    
    @objc public func register(endpoint: String, token: String) {
        guard let url = URL(string: endpoint) else {
            Logger.error("Invalid URL.")
            return
        }

        client = BacktraceRegisteredClient(networkClient: BacktraceNetworkClient(endpoint: url, token: token))
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
