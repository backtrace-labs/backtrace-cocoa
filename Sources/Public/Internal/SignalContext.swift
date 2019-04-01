import Foundation

protocol SignalContext: CustomStringConvertible {
    var allAttributes: Attributes { get }
    var attributes: Attributes { get set }
    var defaultAttributes: Attributes { get }
    func set(faultMessage: String?)
}
