import Foundation

protocol BacktraceError: Error {}

enum NetworkError: BacktraceError {
    case connectionError(Error)
}

enum HttpError: BacktraceError {
    case malformedUrl
    case unknownError
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
    case encodingFailed
}
