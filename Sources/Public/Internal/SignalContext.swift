import Foundation

protocol SignalContext: CustomStringConvertible {
    var attributes: Attributes { get }
    var userAttributes: Attributes { get set }
    var defaultAttributes: Attributes { get }
}
