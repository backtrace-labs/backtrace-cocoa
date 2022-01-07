import Foundation

struct MetricsRequest {

    let request: URLRequest

    private enum Constants {
        static let submissionPath = "/post"
        static let queryItems = { token in ["format": "plcrash", "token": token] }
    }

    init<T: Payload>(url: URL, payload: T) throws {
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

// From: https://gist.github.com/sourleangchhean168/f1a663c8524936af35221f410b588677
private extension Data {
    var prettyPrintedJSONString: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyPrintedString = String(data: data, encoding: .utf8) else { return nil }

        return prettyPrintedString
    }
}

extension MetricsRequest {
    static func writeMetricsRequest<T: Payload>(urlRequest: URLRequest, payload: T) throws -> URLRequest {
        let jsonEncoder = JSONEncoder()
        let body = try jsonEncoder.encode(payload)

        var metricsRequest = urlRequest
        metricsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        metricsRequest.httpBody = body

        BacktraceLogger.debug("Metrics payload JSON: \(body.prettyPrintedJSONString ?? "")")

        return metricsRequest
    }
}
