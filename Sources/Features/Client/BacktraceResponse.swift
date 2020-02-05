import Foundation

struct BacktraceHttpResponseDeserializer {
    let result: Result<BacktraceResponse, BacktraceErrorResponse>
    
    init(httpResponse: HTTPURLResponse, responseData: Data) throws {
        if httpResponse.isSuccess {
            self.result = .success(try JSONDecoder().decode(BacktraceResponse.self, from: responseData))
        } else {
            self.result = .error(try BacktraceErrorResponse(data: responseData))
        }
    }
}

struct BacktraceResponse: Codable {
    let response, rxid: String
    let fingerprint: String?
    let unique: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case response
        case rxid = "_rxid"
        case fingerprint, unique
    }
}

extension BacktraceResponse {
    func result(report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult(.ok, report: report)
    }
}

struct BacktraceErrorResponse: BacktraceError {
    let response: Any
    
    init(data: Data) throws {
        self.response = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

extension BacktraceErrorResponse {
    func result(report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult(.serverError, report: report, message: String(describing: response))
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool {
        return (200...299).contains(self.statusCode)
    }
}
