import Foundation

/// A single log entry in the session timeline.
struct BacktraceSessionLogEntry: Codable {
    let timestamp: TimeInterval
    let level: String
    let message: String
    let attributes: [String: String]?
}
