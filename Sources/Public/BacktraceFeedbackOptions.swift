import Foundation

/// Configuration for the in-app feedback form.
@objc public class BacktraceFeedbackOptions: NSObject {

    /// Whether the email field is required. Default `false`.
    @objc public var isEmailRequired: Bool = false

    /// Whether the email field is visible. Default `true`.
    @objc public var isEmailVisible: Bool = true

    /// Pre-populated text in the description field. Default `nil`.
    @objc public var defaultText: String?

    /// Title shown at the top of the feedback form. Default `"Report a Bug"`.
    @objc public var title: String = "Report a Bug"

    /// Custom form fields appended after the default fields.
    /// Pass `nil` to use only the default email + description fields.
    @objc public var customFields: [BacktraceFeedbackField]?

    @objc public override init() {
        super.init()
    }
}
