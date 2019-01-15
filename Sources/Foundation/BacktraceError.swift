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

enum UrlError: BacktraceError {
    case malformedUrl
}

enum PLCrashReporterError: BacktraceError {
    case fatal
}

enum RepositoryError: BacktraceError {
    case resourceNotFound
    case resourceAlreadyExists
}
