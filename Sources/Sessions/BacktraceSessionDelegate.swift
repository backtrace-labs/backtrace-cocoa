import Foundation

/// Delegate protocol for session lifecycle events.
///
/// Implement this protocol to receive callbacks when session state changes,
/// feedback is submitted, or errors occur during session operations.
@objc public protocol BacktraceSessionDelegate: AnyObject {

    /// Called when a session has started successfully.
    ///
    /// - Parameter sessionUrl: The web dashboard URL for this session, if available.
    @objc optional func sessionDidStart(sessionUrl: String?)

    /// Called when a session could not be started.
    ///
    /// - Parameter error: The error that prevented session start.
    @objc optional func sessionDidFailToStart(error: Error)

    /// Called when a session has been stopped.
    @objc optional func sessionDidStop()

    /// Called when user feedback has been submitted successfully.
    @objc optional func feedbackDidSubmit()

    /// Called when feedback submission failed.
    ///
    /// - Parameter error: The error that caused the failure.
    @objc optional func feedbackDidFailToSubmit(error: Error)
}
