import Foundation

/// Provides session recording, feedback, and log capture functionality to `BacktraceClient`.
@objc public protocol BacktraceSessionProtocol {

    /// The session manager instance. Access session features through this property.
    @objc var sessions: BacktraceSessions { get }

    /// Enable session features with default settings.
    /// Requires `sessionSettings` (with `appToken`) to be set on `BacktraceClientConfiguration`.
    @objc func enableSessions()

    /// Enable session features with the given settings.
    ///
    /// - Parameter settings: Configuration for session recording, feedback, and log capture.
    @objc func enableSessions(_ settings: BacktraceSessionSettings)
}
