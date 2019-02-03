import Foundation

/// Backtrace result statuses.
@objc public enum BacktraceResultStatus: Int {
    /// Server error occurred while sending the data
    case serverError
    /// Successfully sent data to server
    case ok
    /// Client is not registered.
    case notRegistered
    /// Unknown error occurred.
    case unknownError
    /// Client limit reached.
    case limitReached
}

extension BacktraceResultStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .serverError:
            return "serverError"
        case .ok:
            return "ok"
        case .notRegistered:
            return "notRegistered"
        case .unknownError:
            return "unknownError"
        case .limitReached:
            return "limitReached"
        }
    }
}
