import Foundation

final class BacktraceNetworkClient {
    let urlSession: URLSession
    let reachability = NetworkReachability()

    init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    func send(request: URLRequest) async throws -> BacktraceHttpResponse {
        let response = await urlSession.asyncRequest(request)

        if let responseError = response.responseError {
            throw NetworkError.connectionError(responseError)
        }
        guard let urlResponse = response.urlResponse else {
            throw HttpError.unknownError
        }

        return BacktraceHttpResponse(httpResponse: urlResponse, responseData: response.responseData)
    }

    func isNetworkAvailable() -> Bool {
        return reachability.isReachable
    }
}

extension BacktraceNetworkClient {

    func sendMetrics(request: URLRequest) {
        let task = self.urlSession.dataTask(with: request,
                            completionHandler: { (responseData, responseUrl, responseError) in
            // TODO: T16698 - Add retry logic
            if let responseError = responseError {
                Task {
                    await BacktraceLogger.error(responseError)
                }
            }
        })
        task.resume()
    }
    
    /// Sends metrics asynchronously using the async/await API.
    func sendMetricsAsync(request: URLRequest) async {
        do {
            // Asynchronously send the metrics request using the async/await API.
            let (data, response) = try await urlSession.data(for: request)

            // Ensure we have a valid HTTP response.
            guard let httpResponse = response as? HTTPURLResponse else {
                await BacktraceLogger.error("Failed to send metrics: Invalid HTTP response.")
                return
            }

            // Check for HTTP errors.
            if httpResponse.statusCode >= 400 {
                await BacktraceLogger.error("Failed to send metrics: HTTP error \(httpResponse.statusCode).")
                return
            }

            // Log success.
            await BacktraceLogger.debug("Metrics sent successfully. Response: \(httpResponse)")
        } catch {
            // Log the error asynchronously.
            await BacktraceLogger.error("Failed to send metrics with error: \(error)")
        }
    }
}
