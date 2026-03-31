import Foundation

/// Type of input for a custom feedback form field.
@objc public enum BacktraceFeedbackFieldType: Int, Sendable {
    case text = 0
    case email = 1
    case textArea = 2
    case select = 3
}

/// Defines a custom field on the feedback form.
@objc public class BacktraceFeedbackField: NSObject {

    /// Key used when submitting the field value.
    @objc public let key: String

    /// Display label shown to the user.
    @objc public let label: String

    /// Input type for this field.
    @objc public let fieldType: BacktraceFeedbackFieldType

    /// Whether the user must fill in this field before submitting.
    @objc public let required: Bool

    /// Options for `.select` type fields. Ignored for other types.
    @objc public let options: [String]?

    @objc public init(key: String,
                      label: String,
                      fieldType: BacktraceFeedbackFieldType = .text,
                      required: Bool = false,
                      options: [String]? = nil) {
        self.key = key
        self.label = label
        self.fieldType = fieldType
        self.required = required
        self.options = options
        super.init()
    }
}
