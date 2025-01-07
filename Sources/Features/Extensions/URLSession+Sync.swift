import Foundation

extension URLSession {
    typealias Response = (responseData: Data?, urlResponse: HTTPURLResponse?, responseError: Swift.Error?)

    enum Error: Swift.Error {
        case failedToReceiveResponse
    }

    // NOTE: DON'T CALL FROM MAIN THREAD
    func sync(_ urlRequest: URLRequest) -> Response {
        let semaphore = DispatchSemaphore(value: 0)
        var response: Response = Response(nil, nil, Error.failedToReceiveResponse)

        let task = dataTask(with: urlRequest,
                            completionHandler: { (responseData, responseUrl, responseError) in
            response = Response(responseData, responseUrl as? HTTPURLResponse, responseError)
            semaphore.signal()
        })
        task.resume()

        if Thread.isMainThread {
            // if ran from the Main Thread, iOS will kill the app if blocked too long (~20 seconds)
            // https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations
            _ = semaphore.wait(timeout: .now() + .seconds(1))
        } else {
            semaphore.wait()
        }

        return response
    }
    
    /// Asynchronously sends a URL request and returns a `Response`.
    func asyncRequest(_ urlRequest: URLRequest) async -> Response {
        do {
            let (data, response) = try await self.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (nil, nil, Error.failedToReceiveResponse)
            }
            
            return (data, httpResponse, nil)
        } catch {
            return (nil, nil, error)
        }
    }
}
