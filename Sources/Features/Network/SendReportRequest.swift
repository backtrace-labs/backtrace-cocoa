import Foundation

struct SendReportRequest {

    private let request: URLRequest?
    
    private enum Constants {
        static let submissionPath = "/post"
        static let queryItems = { token in ["format": "plcrash", "token": token] }
    }

    init(endpoint: URL, token: String) {
        self.request = try? SendReportRequest.formUrlRequest(endpoint: endpoint, token: token)
    }
    
    init(submissionUrl: URL) {
        self.request = SendReportRequest.form(submissionUrl: submissionUrl)
    }
}

// MARK: - RequestType
extension SendReportRequest: RequestType {
    static func form(submissionUrl: URL) -> URLRequest {
        var urlRequest = URLRequest(url: submissionUrl)
        urlRequest.httpMethod = HttpMethod.post.rawValue
        return urlRequest
    }
    
    static func formUrlRequest(endpoint: URL, token: String) throws -> URLRequest {
        var urlComponents = URLComponents(string: endpoint.absoluteString + Constants.submissionPath)
        urlComponents?.queryItems = Constants.queryItems(token).map(URLQueryItem.init)

        guard let finalUrl = urlComponents?.url else {
            BacktraceLogger.error("Malformed url")
            throw HttpError.malformedUrl
        }
        var request = URLRequest(url: finalUrl)
        request.httpMethod = HttpMethod.post.rawValue
        return request
    }
    
    func urlRequest() throws -> URLRequest {
        guard let urlRequest = request else {
            BacktraceLogger.error("Malformed url")
            throw HttpError.malformedUrl
        }
        return urlRequest
    }
}

// MARK: - MultipartRequestType
extension SendReportRequest: MultipartRequestType {}
