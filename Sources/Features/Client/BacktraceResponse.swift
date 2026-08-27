import Foundation

struct BacktraceHttpResponse: CustomStringConvertible {
    let isSuccess: Bool
    let statusCode: Int
    let description: String

    init(httpResponse: HTTPURLResponse, responseData: Data?) {
        self.isSuccess = httpResponse.isSuccess
        self.statusCode = httpResponse.statusCode
        self.description = """
        HTTP \(httpResponse.statusCode)
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
        return BacktraceResult(isSuccess ? .ok : .serverError,
                               report: report,
                               message: description,
                               submissionDisposition: submissionDisposition)
    }

    private var submissionDisposition: BacktraceSubmissionDisposition {
        if isSuccess {
            return .accepted
        }
        if [408, 425, 429].contains(statusCode) || (500...599).contains(statusCode) {
            return .retryable
        }
        return .permanentFailure
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool {
        return (200...299).contains(self.statusCode)
    }
}
