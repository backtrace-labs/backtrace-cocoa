import Foundation

/// Log severity levels for session log capture.
@objc public enum BacktraceSessionLogLevel: Int, Comparable, Sendable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4

    public static func < (lhs: BacktraceSessionLogLevel, rhs: BacktraceSessionLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .verbose: return "verbose"
        case .debug: return "debug"
        case .info: return "info"
        case .warning: return "warning"
        case .error: return "error"
        }
    }

    /// Maps to the TF wire protocol log level string.
    var wireValue: String {
        switch self {
        case .verbose: return "7"
        case .debug: return "6"
        case .info: return "4"
        case .warning: return "3"
        case .error: return "2"
        }
    }
}
