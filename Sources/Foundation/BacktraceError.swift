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
    case persistenRepositoryInitError(details: String)
    case canNotCreateEntityDescription
}

enum FileError: BacktraceError {
    case unsupportedScheme
    case fileNotExists
    case resourceValueUnavailable
}

extension BacktraceError {
    var backtraceResult: BacktraceResult {
        return BacktraceResult(.unknownError)
    }
}
