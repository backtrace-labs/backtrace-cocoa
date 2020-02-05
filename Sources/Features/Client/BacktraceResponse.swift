import Foundation

struct BacktraceHttpResponse: CustomStringConvertible {
    let isSuccess: Bool
    let description: String
    
    init(httpResponse: HTTPURLResponse, responseData: Data) {
        self.isSuccess = httpResponse.isSuccess
        let responseBody: Any =
            (try? JSONSerialization.jsonObject(with: responseData, options: [.fragmentsAllowed])) ?? ""
        self.description = """
        \(httpResponse)
        \(responseBody)
        """
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
