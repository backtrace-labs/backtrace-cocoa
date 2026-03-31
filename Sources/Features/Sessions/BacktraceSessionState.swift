import Foundation

/// Represents the lifecycle state of a session.
enum BacktraceSessionState: Int, Sendable {
    /// Session object created but not yet started.
    case idle = 0
    /// Session is actively recording events, logs, and screenshots.
    case active = 1
    /// Session is temporarily paused (e.g., app backgrounded or explicit pause).
    /// Timers still exist but skip work. Buffers are preserved.
    case paused = 2
    /// Session has been stopped. No further data is collected.
    /// A new session must be created to resume recording.
    case stopped = 3

    var isCollecting: Bool {
        return self == .active
    }

    var canTransitionToActive: Bool {
        return self == .idle || self == .paused
    }
}
