import Foundation

final class BacktraceNetworkClient {
    
    typealias HttpResponseHandler = (BacktraceHttpResponse?, BacktraceError?) -> Void
    
    let urlSession: URLSession
    let reachability = NetworkReachability()

    init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    func send(request: URLRequest) throws -> BacktraceHttpResponse {
        let response = self.urlSession.sync(request)

        if let responseError = response.responseError {
            throw NetworkError.connectionError(responseError)
        }
        guard let urlResponse = response.urlResponse else {
            throw HttpError.unknownError
        }
        // check result
        return BacktraceHttpResponse(httpResponse: urlResponse, responseData: response.responseData)
    }
    
    func sendAsync(request: URLRequest, handler: @escaping HttpResponseHandler) {
        urlSession.async(request) { response in
            if let responseError = response.responseError {
                handler(nil, NetworkError.connectionError(responseError))
                return
            }
            guard let urlResponse = response.urlResponse else {
                handler(nil, HttpError.unknownError)
                return
            }
            handler(BacktraceHttpResponse(httpResponse: urlResponse, responseData: response.responseData), nil)
        }
    }

    func isNetworkAvailable() -> Bool {
        return reachability.isReachable
    }
}

extension BacktraceNetworkClient {

    func sendMetrics(request: URLRequest) throws -> BacktraceMetricsHttpResponse {
        let response = self.urlSession.sync(request)

        if let responseError = response.responseError {
            throw NetworkError.connectionError(responseError)
        }
        guard let urlResponse = response.urlResponse else {
            throw HttpError.unknownError
        }
        // check result
        return BacktraceMetricsHttpResponse(httpResponse: urlResponse)
    }
}
