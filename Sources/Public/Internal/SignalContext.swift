import Foundation

protocol SignalContext: CustomStringConvertible {
    var allAttributes: Attributes { get }
    var attributes: Attributes { get set }
    // File attachments are stored to disk as URLs
    var attachments: Attachments { get set }
    // File attachments are used in `BacktraceReport` as string paths
    var attachmentPaths: [String] { get }
    func set(faultMessage: String?)
    func set(errorType: String?)
}
