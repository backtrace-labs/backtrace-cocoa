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
            BacktraceLogger.warning("Synchronous network call on the main thread, this is not recommended!")
            // if ran from the Main Thread, iOS will kill the app if blocked too long (~20 seconds)
            // https://developer.apple.com/documentation/xcode/addressing-watchdog-terminations
            _ = semaphore.wait(timeout: .now() + .seconds(1))
        } else {
            semaphore.wait()
        }

        return response
    }
}
