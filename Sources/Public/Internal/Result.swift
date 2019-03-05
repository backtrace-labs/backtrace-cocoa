import Foundation

enum Result<T, E: Error> {
    case success(T)
    case error(E)
}
