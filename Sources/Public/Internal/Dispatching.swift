import Foundation

protocol Dispatching {
    func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void)
}
