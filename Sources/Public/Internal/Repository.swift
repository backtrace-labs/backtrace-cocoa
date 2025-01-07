import Foundation

protocol Repository {
    associatedtype Resource

    func save(_ resource: Resource) async throws
    func delete(_ resource: Resource) async throws
    func getAll() async throws -> [Resource]
    func get(sortDescriptors: [NSSortDescriptor]?, predicate: NSPredicate?, fetchLimit: Int?) async throws -> [Resource]
    func incrementRetryCount(_ resource: Resource, limit: Int) async throws
    func getLatest(count: Int) async throws -> [Resource]
    func getOldest(count: Int) async throws -> [Resource]
    func countResources() async throws -> Int
    func clear() async throws
}
