import Foundation

struct BacktraceMetricsHttpResponse {

    let statusCode: Int

    init(httpResponse: HTTPURLResponse) {
        self.statusCode = httpResponse.statusCode
    }
}

extension BacktraceMetricsHttpResponse {
    func result() -> BacktraceMetricsResult {
        return BacktraceMetricsResult(statusCode)
    }
}
