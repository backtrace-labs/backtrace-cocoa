import Foundation

protocol Dispatching: Sendable {
    func dispatch(_ block: @escaping @Sendable () -> Void, completion: @escaping @Sendable () -> Void)
}
