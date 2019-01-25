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

extension BacktraceError {
    var backtraceResult: BacktraceResult {
        return BacktraceResult(.unknownError)
    }
}
