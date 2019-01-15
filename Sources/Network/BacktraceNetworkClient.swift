//
//  BacktraceNetworkClient.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 09/12/2018.
//

import Foundation

public class BacktraceNetworkClient {
    private let request: SendCrashRequest
    private let session: URLSession

    init(endpoint: URL, token: String, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
        self.request = SendCrashRequest(endpoint: endpoint, token: token)
    }
}

extension BacktraceNetworkClient: NetworkClientType {
    public func send(_ report: Data) throws {
        Logger.debug("Sending crash report.")
        let urlRequest = try self.request.urlRequest()
        let response = session.sync(urlRequest, data: report)
        Logger.debug("Response status code: \(response.urlResponse?.statusCode ?? -1)")
    }

    public func send(_ data: Data, completion: ResponseCompletion?) {
        do {
            let urlRequest = try self.request.urlRequest()
            Logger.info(urlRequest.description)
            let task = session.uploadTask(with: urlRequest, from: data) { (_, urlResponse, error) in
                completion?(urlResponse, error)
            }
            task.resume()
        } catch {
            Logger.error(error.localizedDescription)
            completion?(nil, error)
        }
    }
}
