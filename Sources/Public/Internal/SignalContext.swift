import Foundation

protocol SignalContext: CustomStringConvertible {
    var allAttributes: Attributes { get }
    var attributes: Attributes { get set }
    func set(faultMessage: String?)
}
