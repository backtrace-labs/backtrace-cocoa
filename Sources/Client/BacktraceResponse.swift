import Foundation

enum Result<T, E: Error> {
    case success(T)
    case error(E)
}

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
    
    enum CodingKeys: String, CodingKey {
        case response
        case rxid = "_rxid"
        case fingerprint, unique
    }
}

extension BacktraceResponse {
    func result(backtraceReport: BacktraceCrashReport) -> BacktraceResult {
        return BacktraceResult(.ok, message: "Ok.", backtraceReport: backtraceReport)
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
    func result(backtraceReport: BacktraceCrashReport) -> BacktraceResult {
        return BacktraceResult(.serverError, message: error.message, backtraceReport: backtraceReport)
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool {
        return (200...299).contains(self.statusCode)
    }
}
