import Foundation

extension URLSession {
    typealias Response = (responseData: Data?, urlResponse: HTTPURLResponse?, responseError: Swift.Error?)

    enum Error: Swift.Error {
        case failedToReceiveResponse
    }

    func sync(_ urlRequest: URLRequest) -> Response {
        let semaphore = DispatchSemaphore(value: 0)
        var response: Response = Response(nil, nil, Error.failedToReceiveResponse)

        let task = dataTask(with: urlRequest,
                            completionHandler: { (responseData, responseUrl, responseError) in
            response = Response(responseData, responseUrl as? HTTPURLResponse, responseError)
            semaphore.signal()
        })
        task.resume()
        semaphore.wait()

        return response
    }
}
