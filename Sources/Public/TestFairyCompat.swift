import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - TestFairy Compatibility Shim
//
// Provides a `TestFairy` class that maps legacy TestFairy SDK methods to the new
// Backtrace session API. Every method is marked `@available(*, deprecated)` with
// a message pointing to the new API.
//
// Usage: Existing TF customers can swap `import TestFairy` with `import Backtrace`
// and get compile-time migration guidance. They must first configure BacktraceClient.shared.

/// TestFairy-compatible API for migrating existing integrations.
///
/// All methods forward to `BacktraceClient.shared?.sessions`.
/// Configure `BacktraceClient.shared` before calling any of these methods.
@available(*, deprecated, message: "Use BacktraceClient with session features instead. See MIGRATION.md for details.")
@objc public class TestFairy: NSObject {

    /// Internal storage for the TF app token passed via `begin()`.
    private static var appToken: String?

    // MARK: - Session Management

    @available(*, deprecated, message: "Use BacktraceClient(configuration:) + enableSessions()")
    @objc public static func begin(_ appToken: String) {
        self.appToken = appToken
        guard let client = BacktraceClient.shared else {
            BacktraceLogger.warning("TestFairy.begin: BacktraceClient.shared is not configured. Set it up first.")
            return
        }
        // If sessionSettings already has appToken, use it; otherwise inject the TF token
        if client.sessions.settings.appToken == nil {
            client.sessions.settings.appToken = appToken
        }
        client.enableSessions()
    }

    @available(*, deprecated, message: "Use BacktraceClient(configuration:) + enableSessions(BacktraceSessionSettings())")
    @objc public static func begin(_ appToken: String, withOptions options: [String: Any]) {
        self.appToken = appToken
        guard let client = BacktraceClient.shared else {
            BacktraceLogger.warning("TestFairy.begin: BacktraceClient.shared is not configured.")
            return
        }
        if client.sessions.settings.appToken == nil {
            client.sessions.settings.appToken = appToken
        }
        // Map common TF options to session settings
        if let screenshotInterval = options["screenshot-interval"] as? TimeInterval {
            client.sessions.settings.screenshotInterval = screenshotInterval
        }
        client.enableSessions()
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.stop()")
    @objc public static func stop() {
        BacktraceClient.shared?.sessions.stop()
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.pause()")
    @objc public static func pause() {
        BacktraceClient.shared?.sessions.pause()
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.resume()")
    @objc public static func resume() {
        BacktraceClient.shared?.sessions.resume()
    }

    // MARK: - Logging

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.log(_:level:)")
    @objc public static func log(_ message: String) {
        BacktraceClient.shared?.sessions.log(message, level: .info)
    }

    // MARK: - User Identity & Attributes

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.setUserIdentifier(_:)")
    @objc public static func setUserId(_ userId: String) {
        BacktraceClient.shared?.sessions.setUserIdentifier(userId)
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.setUserIdentifier(_:) + setAttribute(_:value:)")
    @objc public static func identify(_ correlationId: String, traits: [String: Any]?) {
        BacktraceClient.shared?.sessions.setUserIdentifier(correlationId)
        if let traits = traits {
            for (key, value) in traits {
                BacktraceClient.shared?.sessions.setAttribute(key, value: "\(value)")
            }
        }
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.setAttribute(_:value:)")
    @objc public static func setAttribute(_ key: String, withValue value: String) -> Bool {
        BacktraceClient.shared?.sessions.setAttribute(key, value: value)
        return true
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.addEvent(_:)")
    @objc public static func addEvent(_ name: String) {
        BacktraceClient.shared?.sessions.addEvent(name)
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.addEvent(_:)")
    @objc public static func checkpoint(_ name: String) {
        BacktraceClient.shared?.sessions.addEvent(name)
    }

    // MARK: - Feedback

    #if os(iOS)
    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.showFeedbackForm()")
    @objc public static func showFeedbackForm() {
        BacktraceClient.shared?.sessions.showFeedbackForm()
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.showFeedbackForm()")
    @objc public static func pushFeedbackController() {
        BacktraceClient.shared?.sessions.showFeedbackForm()
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.sendFeedback(_:)")
    @objc public static func sendUserFeedback(_ feedback: String) {
        BacktraceClient.shared?.sessions.sendFeedback(feedback)
    }

    // MARK: - Screenshots & Privacy

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.captureScreenshot()")
    @objc public static func takeScreenshot() {
        BacktraceClient.shared?.sessions.captureScreenshot()
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.hideView(_:)")
    @objc public static func hideView(_ view: UIView) {
        BacktraceClient.shared?.sessions.hideView(view)
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.unhideView(_:)")
    @objc public static func unhideView(_ view: UIView) {
        BacktraceClient.shared?.sessions.unhideView(view)
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.setScreenName(_:)")
    @objc public static func setScreenName(_ name: String) {
        BacktraceClient.shared?.sessions.setScreenName(name)
    }
    #endif

    // MARK: - Configuration

    @available(*, deprecated, message: "Set BacktraceSessionSettings.collectorURL instead")
    @objc public static func setServerEndpoint(_ endpoint: String) {
        if let url = URL(string: endpoint) {
            BacktraceClient.shared?.sessions.settings.collectorURL = url
        }
    }

    @available(*, deprecated, message: "Set BacktraceSessionSettings.encryptionPublicKey instead")
    @objc public static func setPublicKey(_ publicKey: String) {
        BacktraceClient.shared?.sessions.settings.encryptionPublicKey = publicKey
    }

    // MARK: - Session Info

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.sessionURL")
    @objc public static func sessionUrl() -> String? {
        return BacktraceClient.shared?.sessions.sessionURL
    }

    @available(*, deprecated, message: "Use BacktraceClient.shared?.sessions.isActive")
    @objc public static func sdkVersion() -> String {
        return "backtrace-cocoa-2.1.0"
    }
}
