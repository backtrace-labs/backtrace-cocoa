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
    @objc var pendingCrashReport: String? { get }
    @objc func generateLiveReport() -> String
    /// Sends a crash report to Backtrace services.
    ///
    /// - Parameters:
    ///   - error: catched error
    ///   - completion:
    @objc func send(_ error: Error, completion: ((Error?) -> Void)?)
}

/// Provides the default implementation of BacktraceClientProviding protocol.
@objc public class BacktraceClient: NSObject {

    /// Shared instance of BacktraceClient class.
    @objc public static let shared = BacktraceClient()
    private var client: BacktraceClientType & BacktraceClientTypeDebuggable
    private let dispatcher: Dispatcher

    private override init() {
        self.client = BacktraceUnregisteredClient()
        self.dispatcher = Dispatcher()
        super.init()
    }
}

// MARK: - BacktraceClientProviding
extension BacktraceClient: BacktraceClientProviding {
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

    @objc public var pendingCrashReport: String? {
        return client.pendingCrashReport
    }

    @objc public func generateLiveReport() -> String {
        return client.generateLiveReport()
    }

    @objc public func send(_ error: Error, completion: ((Error?) -> Void)? = nil) {
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                try self.client.send(error)
                completion?(nil)
            } catch {
                Logger.error(error)
                completion?(error)
            }
            }, completion: {
                Logger.debug("Finished")
        })
    }
}
