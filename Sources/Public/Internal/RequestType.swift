import Foundation

protocol RequestType {
    var baseURL: URL { get }
    var path: String { get }
    var method: HttpMethod { get }
    var queryItems: [String: String] { get }
}

extension RequestType {
    func urlRequest() throws -> URLRequest {
        var urlComponents = URLComponents(string: baseURL.absoluteString + path)
        urlComponents?.queryItems = queryItems.map(URLQueryItem.init)

        guard let finalUrl = urlComponents?.url else {
            BacktraceLogger.error("Malformed url")
            throw HttpError.malformedUrl
        }
        var request = URLRequest(url: finalUrl)
        request.httpMethod = method.rawValue
        return request
    }
}
