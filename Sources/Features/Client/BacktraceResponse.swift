import Foundation

struct BacktraceHttpResponseDeserializer {
    let result: Result<BacktraceResponse, BacktraceErrorResponse>
    
    init(httpResponse: HTTPURLResponse, responseData: Data) throws {
        let jsonDeserializer = JSONDecoder()
        if httpResponse.isSuccess {
            self.result = .success(try jsonDeserializer.decode(BacktraceResponse.self, from: responseData))
        } else {
            self.result = .error(try jsonDeserializer.decode(BacktraceErrorResponse.self, from: responseData))
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

struct BacktraceErrorResponse: Codable, BacktraceError {
    let error: ResponseError
    
    struct ResponseError: Codable {
        let code: Int
        let message: String
    }
}

extension BacktraceErrorResponse {
    func result(report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult(.serverError, report: report, message: error.message)
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool {
        return (200...299).contains(self.statusCode)
    }
}
