import Nimble
import CoreData
import Quick
@testable import Backtrace
#if SWIFT_PACKAGE
import Foundation
#endif

private enum MockTestError: Error, Equatable {
    case somethingWentWrong
}

final class NSManagedObjectContextExtensionTests: QuickSpec {
    override func spec() {
        describe("performAndWaitThrowing") {
            throwingContext("with an in-memory NSManagedObjectContext") {
                var inMemoryContext: NSManagedObjectContext!
                
                beforeEach {
                    // in-memory context
                    let mom = NSManagedObjectModel()
                    let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: mom)
                    try? persistentStoreCoordinator.addPersistentStore(ofType: NSInMemoryStoreType,
                                                                       configurationName: nil,
                                                                       at: nil,
                                                                       options: nil)
                    inMemoryContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                    inMemoryContext.persistentStoreCoordinator = persistentStoreCoordinator
                }
                
                afterEach {
                    inMemoryContext = nil
                }
                
                throwingIt("returns the correct value if the block succeeds") {
                    let expected = "expected result"
                    let result: String = try inMemoryContext.performAndWaitThrowing {
                        // Return a simple string
                        return expected
                    }
                    expect(result).to(equal(expected))
                }
                
                throwingIt("rethrows an error if the block fails") {
                    expect {
                        try inMemoryContext.performAndWaitThrowing {
                            throw MockTestError.somethingWentWrong
                        }
                    }
                    .to(throwError(MockTestError.somethingWentWrong))
                }
            }
        }
    }
}
