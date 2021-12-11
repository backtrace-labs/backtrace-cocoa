import Foundation

struct MetricsRequest {

    let request: URLRequest
    
    private enum Constants {
        static let submissionPath = "/post"
        static let queryItems = { token in ["format": "plcrash", "token": token] }
    }
    
    init<T: Event>(url: URL, payload: Payload<T>) throws {
        let request = MetricsRequest.form(submissionUrl: url)
        self.request = try MetricsRequest.writeMetricsRequest(urlRequest: request, payload: payload)
    }
}

extension MetricsRequest {
    static func form(submissionUrl: URL) -> URLRequest {
        var urlRequest = URLRequest(url: submissionUrl)
        urlRequest.httpMethod = HttpMethod.post.rawValue
        return urlRequest
    }
}

extension MetricsRequest {
    static func writeMetricsRequest<T: Event>(urlRequest: URLRequest, payload: Payload<T>) throws -> URLRequest {
        let jsonEncoder = JSONEncoder()
        let body = try jsonEncoder.encode(payload)

        var metricsRequest = urlRequest
        metricsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        metricsRequest.httpBody = body
    //    metricsRequest.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        return metricsRequest
    }
}
