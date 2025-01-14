import Foundation

protocol BacktraceError: Error {
    var backtraceStatus: BacktraceReportStatus { get }
}

extension Error {
    var backtraceStatus: BacktraceReportStatus {
        return .unknownError
    }
}

enum NetworkError: BacktraceError {
    case connectionError(Error)
}

enum HttpError: BacktraceError {
    case malformedUrl(URL)
    case fileCreationFailed(URL)
    case fileWriteFailed
    case attachmentError(String)
    case multipartFormError(Error)
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

extension HttpError {
    var backtraceStatus: BacktraceReportStatus {
        switch self {
        case .malformedUrl, .fileCreationFailed, .fileWriteFailed, .attachmentError, .multipartFormError:
            return .unknownError
        case .unknownError:
            return .serverError
        }
    }
}

extension NetworkError {
    var localizedDescription: String {
        switch self {
        case .connectionError(let error):
            return error.localizedDescription
        }
    }
}

extension HttpError {
    var localizedDescription: String {
        switch self {
        case .malformedUrl(let url):
            return "Provided URL cannot be parsed: \(url)."
        case .fileCreationFailed(let url):
            return "File Error occurred: \(url)."
        case .fileWriteFailed:
            return "File Write Error occurred."
        case .attachmentError(let string):
            return "Attachment Error occurred: \(string)."
        case .multipartFormError(let error):
            return "Multipart Form Error occurred: \(error.localizedDescription)."
        case .unknownError:
            return "Unknown error occurred."
        }
    }
}

extension RepositoryError {
    var localizedDescription: String {
        switch self {
        case .resourceNotFound:
            return "Previously saved resource cannot be found."
        case .resourceAlreadyExists:
            return "Resource already exists in the database."
        case .persistentRepositoryInitError(let details):
            return "An unexpected error occurred while trying to instantiate database: \(details)."
        case .canNotCreateEntityDescription:
            return "Resource cannot be added to the database."
        }
    }
}

extension FileError {
    var localizedDescription: String {
        switch self {
        case .unsupportedScheme: return "Unsupported URL scheme."
        case .fileNotExists: return "File does not exist."
        case .resourceValueUnavailable: return "A value for file resource cannot be found."
        case .noCacheDirectory: return "Cache directory does not exist."
        case .fileNotWritten: return "File cannot be saved."
        case .invalidPropertyList: return "Invalid property list."
        }
    }
}

extension CodingError {
    var localizedDescription: String {
        switch self {
        case .encodingFailed: return "Encoding failed."
        }
    }
}
