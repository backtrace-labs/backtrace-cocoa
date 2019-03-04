import Foundation

protocol Repository {
    associatedtype Resource

    func save(_ resource: Resource) throws
    func delete(_ resource: Resource) throws
    func getAll() throws -> [Resource]
    func get(sortDescriptors: [NSSortDescriptor]?, predicate: NSPredicate?, fetchLimit: Int?) throws -> [Resource]
    func incrementRetryCount(_ resource: Resource, limit: Int) throws
    func getLatest(count: Int) throws -> [Resource]
    func getOldest(count: Int) throws -> [Resource]
    func countResources() throws -> Int
    func clear() throws
}
