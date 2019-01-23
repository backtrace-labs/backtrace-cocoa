import Foundation

/// Backtrace result statuses.
enum BacktraceResultStatus {
    case serverError(message: String, code: Int)
    case ok(response: String)
    case notRegisterd
    case unknownError
}

extension BacktraceResultStatus: CustomStringConvertible {
    var description: String {
        switch self {
        case .serverError(let message, _):
            return message
        case .ok(let response):
            return response
        case .notRegisterd:
            return "Backtrace client is not registered."
        case .unknownError:
            return "Unknown error."
        }
    }
}
