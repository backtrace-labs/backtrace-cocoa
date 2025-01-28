import Foundation
import CoreData

enum PerformAndWaitError: Error {
    case blockDidNotRun
}

extension NSManagedObjectContext {

    /// Runs `block` inside `performAndWait`, captures any thrown error and returns the result.
    ///
    /// - Parameter block: A closure that either returns `T` or throws an error
    /// - Returns: The value returned by `block`
    /// - Throws:
    ///     - Rethrows any error from `block`, or `PerformAndWaitError.blockDidNotRun` if the closure never produced a result
    func performAndWaitThrowing<T>(_ block: () throws -> T) throws -> T {
        var result: T!
        var thrownError: Error?
        performAndWait {
            do {
                result = try block()
            } catch {
                thrownError = error
            }
        }
        if let thrownError = thrownError {
            throw thrownError
        }
        return result
    }
    
    // Swift 5 approach
    func performAndWaitThrowingSwift5<T>(_ block: () throws -> T) throws -> T {
        var result: Swift.Result<T, Error>?
            performAndWait {
                // Captures returned value or throws error
                result = Swift.Result(catching: block)
            }
            guard let outcome = result else {
                throw PerformAndWaitError.blockDidNotRun
            }
            return try outcome.get()
        }
}
