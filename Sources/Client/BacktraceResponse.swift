import Foundation

struct BacktraceHtttpResponseDeserializer {
    let response: BacktraceResponse
    
    init(httpResponse: HTTPURLResponse, responseData: Data) throws {
        let jsonDeserializer = JSONDecoder()
        if httpResponse.isSuccess {
            self.response = (try jsonDeserializer.decode(BacktraceResponse.self, from: responseData))
        } else {
            let errorResponse = try jsonDeserializer.decode(BacktraceErrorResponse.self, from: responseData)
            throw errorResponse
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
    var backtraceResult: BacktraceResult {
        return BacktraceResult(status: .ok, message: self.response)
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
    var backtraceResult: BacktraceResult {
        return BacktraceResult(status: .serverError, message: self.error.message)
    }
}

private extension HTTPURLResponse {
    var isSuccess: Bool {
        return (200...299).contains(self.statusCode)
    }
}
