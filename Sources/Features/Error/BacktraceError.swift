import Foundation

protocol BacktraceError: Error {}

enum FlowError: BacktraceError {
    case unexpectedState
}

enum HttpError: BacktraceError {
    case malformedUrl
    case connectionError(Error)
    case unknownError
}

enum PLCrashReporterError: BacktraceError {
    case fatal
}

enum RepositoryError: BacktraceError {
    case resourceNotFound
    case resourceAlreadyExists
    case persistentRepositoryInitError(details: String)
    case canNotCreateEntityDescription
}

enum FileError: BacktraceError {
    case unsupportedScheme
    case fileNotExists
    case resourceValueUnavailable
    case noCacheDirectory
    case fileNotWritten
    case invalidPropertyList
}

enum CodingError: BacktraceError {
    case decodingFailed
    case encodingFailed
}
