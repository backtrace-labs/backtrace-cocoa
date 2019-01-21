//
//  BacktraceNetworkClientMock.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 17/01/2019.
//

import Foundation

@testable import Backtrace

final class BacktraceNetworkClientMock: NetworkClientType {
    enum Configuration {
        case invalidToken
        case invalidEndpoint
        case validCredentials
    }
    
    func send(_ report: Data) throws -> BacktraceResponse {
        switch config {
        case .invalidToken:
            throw BacktraceErrorResponse(error: BacktraceErrorResponse.ResponseError(code: 1897, message: "Forbidden"))
        case .invalidEndpoint:
            throw HttpError.unknownError
        case .validCredentials:
            return BacktraceResponse(response: "Ok.", rxid: "xx-xx", fingerprint: "xx-xx", unique: true)
        }
    }
    
    let config: Configuration
    
    init(config: Configuration) {
        self.config = config
    }
}
