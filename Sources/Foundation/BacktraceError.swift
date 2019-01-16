//
//  BacktraceError.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 09/12/2018.
//

import Foundation

protocol BacktraceError: Error {}

enum FlowError: BacktraceError {
    case unexpectedState
}

enum HttpError: BacktraceError {
    case malformedUrl
    case serverError(Error)
    case unknownError
}

enum PLCrashReporterError: BacktraceError {
    case fatal
}

enum RepositoryError: BacktraceError {
    case resourceNotFound
    case resourceAlreadyExists
}
