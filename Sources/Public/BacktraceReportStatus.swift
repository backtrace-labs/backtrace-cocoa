import Foundation

/// Backtrace result statuses.
@objc public enum BacktraceReportStatus: Int {
    /// Server error occurred while sending the data.
    case serverError
    /// Successfully sent data to server.
    case ok
    /// Debugger is attached.
    case debuggerAttached
    /// Unknown error occurred.
    case unknownError
    /// Client limit reached.
    case limitReached
}

extension BacktraceReportStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .serverError:
            return "A server error occurred."
        case .ok:
            return "OK."
        case .debuggerAttached:
            return "Application does not allow to attach the debugger."
        case .unknownError:
            return "An unknown server error occurred."
        case .limitReached:
            return "Application limit reached."
        }
    }
}
