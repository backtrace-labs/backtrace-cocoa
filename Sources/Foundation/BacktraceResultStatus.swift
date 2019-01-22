import Foundation

/// Backtrace result statuses.
@objc public enum BacktraceResultStatus: Int {
    case serverError
    case ok
    case notRegisterd
}
