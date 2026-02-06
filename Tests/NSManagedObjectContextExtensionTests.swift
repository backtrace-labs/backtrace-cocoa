import Testing
import CoreData
import Foundation
@testable import Backtrace

private enum MockTestError: Error, Equatable {
    case somethingWentWrong
}

@Suite struct NSManagedObjectContextExtensionTests {

    private func makeInMemoryContext() -> NSManagedObjectContext {
        let mom = NSManagedObjectModel()
        let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: mom)
        _ = try? persistentStoreCoordinator.addPersistentStore(ofType: NSInMemoryStoreType,
                                                               configurationName: nil,
                                                               at: nil,
                                                               options: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = persistentStoreCoordinator
        return context
    }

    @Test("Returns the correct value if the block succeeds")
    func returnsCorrectValue() throws {
        let inMemoryContext = makeInMemoryContext()
        let expected = "expected result"
        let result: String = try inMemoryContext.performAndWaitThrowing {
            return expected
        }
        #expect(result == expected)
    }

    @Test("Rethrows an error if the block fails")
    func rethrowsError() throws {
        let inMemoryContext = makeInMemoryContext()
        #expect {
            try inMemoryContext.performAndWaitThrowing {
                throw MockTestError.somethingWentWrong
            }
        } throws: {
            ($0 as? MockTestError) == .somethingWentWrong
        }
    }
}
