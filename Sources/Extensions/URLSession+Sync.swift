//
//  URLSession+Sync.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 06/01/2019.
//

import Foundation

extension URLSession {
    typealias Response = (responseData: Data?, urlResponse: HTTPURLResponse?, reponseError: Error?)
    func sync(_ urlRequest: URLRequest, data: Data?) -> Response {
        let semaphore = DispatchSemaphore(value: 0)
        var response: Response

        let task = uploadTask(with: urlRequest, from: data,
                              completionHandler: { (responseData, responseUrl, responseError) in
            response = Response(responseData, responseUrl as? HTTPURLResponse, responseError)
            semaphore.signal()
        })
        task.resume()
        semaphore.wait()

        return response
    }
}
