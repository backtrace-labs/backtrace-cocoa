import Foundation

protocol SignalContext: CustomStringConvertible {
    var allAttributes: Attributes { get }
    // We use attachment paths as strings in our report send functions
    var attachmentPathsArray: [ String ] { get }
    var attributes: Attributes { get set }
    var attachments: Attachments { get set }
    func set(faultMessage: String?)
    func set(errorType: String?)
}
