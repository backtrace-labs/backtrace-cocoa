//
//  RequestType.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 06/01/2019.
//

import Foundation

protocol RequestType {
    var baseURL: URL { get }
    var path: String { get }
    var method: Method { get }
    var queryItems: [String: String] { get }
}

extension RequestType {
    func urlRequest() throws -> URLRequest {
        var urlComponents = URLComponents(string: baseURL.absoluteString + path)
        urlComponents?.queryItems = queryItems.map(URLQueryItem.init)

        guard let finalUrl = urlComponents?.url else {
            Logger.error("Malformed error")
            throw UrlError.malformedUrl
        }
        var request = URLRequest(url: finalUrl)
        request.httpMethod = method.rawValue
        return request
    }
}
