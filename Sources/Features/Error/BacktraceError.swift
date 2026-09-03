import Foundation

protocol BacktraceError: Error {
    var backtraceStatus: BacktraceReportStatus { get }
}

extension Error {
    var backtraceStatus: BacktraceReportStatus {
        return .unknownError
    }

    /// Delivery policy for failures thrown before an HTTP response is available.
    ///
    /// Invalid submission URL configuration cannot recover through repository replay.
    /// Network failures without a response remain retryable because connectivity may recover later.
    var backtraceSubmissionDisposition: BacktraceSubmissionDisposition {
        if let httpError = self as? HttpError {
            switch httpError {
            case .malformedUrl:
                return .permanentFailure
            case .unknownError:
                return .retryable
            }
        }

        if let networkError = self as? NetworkError {
            switch networkError {
            case .connectionError(let underlyingError):
                return underlyingError.backtraceSubmissionDisposition
            case .cancelled:
                return .retryable
            }
        }

        let error = self as NSError
        guard error.domain == NSURLErrorDomain else {
            return .retryable
        }

        switch error.code {
        case NSURLErrorBadURL,
             NSURLErrorUnsupportedURL,
             NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return .permanentFailure
        default:
            return .retryable
        }
    }
}

enum NetworkError: BacktraceError {
    case connectionError(Error)
    case cancelled
}

enum HttpError: BacktraceError {
    case malformedUrl(URL)
    case unknownError
}

enum RepositoryError: BacktraceError {
    case resourceNotFound
    case resourceAlreadyExists
    case repositoryShutdown
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

enum SysctlError: BacktraceError {
    case sysctlFailed(String?)
    case invalidUTF8(String?)
}

extension HttpError {
    var backtraceStatus: BacktraceReportStatus {
        switch self {
        case .malformedUrl:
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
        case .cancelled:
            return "Submission was cancelled."
        }
    }
}

extension Error {
    /// Whether a submission stopped because SDK shutdown cancelled transport before an HTTP response was available.
    /// A completed HTTP response is never represented as cancellation.
    var isBacktraceCancellation: Bool {
        if let networkError = self as? NetworkError {
            switch networkError {
            case .cancelled:
                return true
            case .connectionError(let underlyingError):
                return underlyingError.isBacktraceCancellation
            }
        }

        let error = self as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}

extension HttpError {
    var localizedDescription: String {
        switch self {
        case .malformedUrl: return "Provided URL cannot be parsed."
        case .unknownError: return "Unknown error occurred."
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
        case .repositoryShutdown:
            return "Repository activity has been stopped."
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
