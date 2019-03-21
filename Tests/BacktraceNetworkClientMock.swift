import Foundation

@testable import Backtrace

final class BacktraceNetworkClientMock: BacktraceApiProtocol {
    var delegate: BacktraceClientDelegate?
    
    var successfulSendTimestamps: [TimeInterval] = []
    
    enum Configuration {
        case invalidToken
        case invalidEndpoint
        case validCredentials
        case limitReached
    }
    
    static func invalidTokenResponse(_ report: BacktraceReport) -> BacktraceResult {
        return BacktraceErrorResponse(error: BacktraceErrorResponse.ResponseError(code: 1897, message: "Forbidden"))
            .result(backtraceReport: report)
    }
    
    static func invalidCredentials(_ report: BacktraceReport) -> BacktraceResult {
        return BacktraceResponse(response: "Ok.", rxid: "xx-xx", fingerprint: "xx-xx", unique: true).result(backtraceReport: report)
    }
    
    static func limitReachedResponse(_ report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult.limitReached(report)
    }
    
    func send(_ report: BacktraceReport) throws -> BacktraceResult {
        switch config {
        case .invalidToken:
            return BacktraceNetworkClientMock.invalidTokenResponse(report)
        case .invalidEndpoint:
            throw HttpError.unknownError
        case .validCredentials:
            return BacktraceNetworkClientMock.invalidCredentials(report)
        case .limitReached:
            return BacktraceNetworkClientMock.limitReachedResponse(report)
        }
    }
    
    let config: Configuration
    
    init(config: Configuration) {
        self.config = config
    }
}
