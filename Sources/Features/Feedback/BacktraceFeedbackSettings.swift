import Foundation

/// Trigger methods for presenting the feedback form.
@objc public enum BacktraceFeedbackTrigger: Int {
    /// No automatic trigger.
    case none = 0
    /// Shake gesture triggers feedback form.
    case shake = 1
    /// Screenshot triggers feedback form.
    case screenshot = 2
    /// Both shake and screenshot trigger feedback form.
    case both = 3
}

/// Configuration settings for the user feedback feature.
@objc public class BacktraceFeedbackSettings: NSObject {

    /// Whether the email field is visible in the feedback form. Default: true.
    @objc public var emailFieldVisible: Bool = true

    /// Whether the email field is mandatory. Default: false.
    @objc public var emailMandatory: Bool = false

    /// Trigger method for presenting the feedback form. Default: .none.
    @objc public var trigger: BacktraceFeedbackTrigger = .none

    /// Enable feedback feature. Default: false.
    @objc public var enabled: Bool = false

    /// Debounce interval for trigger events in seconds. Default: 2.0.
    @objc public var triggerDebounceSeconds: TimeInterval = 2.0
}
