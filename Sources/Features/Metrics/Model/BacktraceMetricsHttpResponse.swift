import Foundation

struct BacktraceMetricsHttpResponse {

    let statusCode: Int

    init(httpResponse: HTTPURLResponse, responseData: Data?) {
        self.statusCode = httpResponse.statusCode
    }
}

extension BacktraceMetricsHttpResponse {
    func result() -> BacktraceMetricsResult {
        return BacktraceMetricsResult(statusCode)
    }
}
