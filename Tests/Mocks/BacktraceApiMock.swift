import Foundation

@testable import Backtrace

final class BacktraceApiMock: BacktraceApiProtocol {
    weak var delegate: BacktraceClientDelegate?
    
    var successfulSendTimestamps: [TimeInterval] = []
    
    enum Configuration {
        case invalidToken
        case invalidEndpoint
        case validCredentials
        case limitReached
    }
    
    static func invalidTokenResponse(_ report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult(.serverError, report: report, message: "Invalid Token")
    }
    
    static func invalidCredentials(_ report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult(.ok, report: report, message: "Invalid Credentials")
    }
    
    static func limitReachedResponse(_ report: BacktraceReport) -> BacktraceResult {
        return BacktraceResult(.limitReached, report: report)
    }
    
    func send(_ report: BacktraceReport) throws -> BacktraceResult {
        switch config {
        case .invalidToken:
            return BacktraceApiMock.invalidTokenResponse(report)
        case .invalidEndpoint:
            throw HttpError.unknownError
        case .validCredentials:
            return BacktraceApiMock.invalidCredentials(report)
        case .limitReached:
            return BacktraceApiMock.limitReachedResponse(report)
        }
    }
    
    let config: Configuration
    
    init(config: Configuration) {
        self.config = config
    }
}
