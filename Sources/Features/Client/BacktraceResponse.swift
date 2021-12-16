import Foundation

struct BacktraceHttpResponse: CustomStringConvertible {
    let isSuccess: Bool
    let description: String

    init(httpResponse: HTTPURLResponse, responseData: Data?) {
        self.isSuccess = httpResponse.isSuccess
        self.description = """
        \(httpResponse)
        \(responseData.jsonBody)
        """
    }
}

private extension Optional where Wrapped == Data {
    var jsonBody: Any {
        switch self {
        case .none:
            return ""
        case .some(let data):
            return (try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])) ?? ""
        }
    }
}

extension BacktraceHttpResponse {
    func result(report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult(isSuccess ? .ok : .serverError, report: report, message: description)
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool {
        return (200...299).contains(self.statusCode)
    }
}
