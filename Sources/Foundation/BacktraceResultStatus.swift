import Foundation

/// Backtrace result statuses.
@objc public enum BacktraceResultStatus: Int {
    case serverError
    case ok
    case notRegisterd
}

extension BacktraceResultStatus {
    var messageDescription: String {
        switch self {
        case .serverError:
            return "Unknown server error occurred."
        case .ok:
            return "Ok."
        case .notRegisterd:
            return "Backtrace client is not registered."
        }
    }
}
