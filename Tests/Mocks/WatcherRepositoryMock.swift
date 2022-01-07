import Foundation
@testable import Backtrace

final class WatcherRepositoryMock<Resource: BacktraceReport> {
    class StoredResource {
        let resource: Resource
        var retryCount: Int = 0

        init(_ resource: Resource) {
            self.resource = resource
        }
    }
    var storage: [StoredResource] = []

    func retryCount(for resource: Resource) -> Int {
        if let idx = storage.firstIndex(where: { $0.resource == resource }) {
            return storage[idx].retryCount
        }
        return 0
    }
}

extension WatcherRepositoryMock: Repository {

    func save(_ resource: Resource) throws {
        storage.append(StoredResource(resource))
    }

    func delete(_ resource: Resource) throws {
        if let idx = storage.firstIndex(where: { $0.resource == resource }) {
            storage.remove(at: idx)
        }
    }

    func getAll() throws -> [Resource] {
        return storage.map { $0.resource }
    }

    func get(sortDescriptors: [NSSortDescriptor]?, predicate: NSPredicate?, fetchLimit: Int?) throws -> [Resource] {
        return []
    }

    func incrementRetryCount(_ resource: Resource, limit: Int) throws {
        if let idx = storage.firstIndex(where: { $0.resource == resource }) {
            storage[idx].retryCount += 1
        }
    }

    func getLatest(count: Int) throws -> [Resource] {
        return Array(storage.map { $0.resource }.prefix(count))
    }

    func getOldest(count: Int) throws -> [Resource] {
        return Array(storage.map { $0.resource }.suffix(count))
    }

    func countResources() throws -> Int {
        return storage.count
    }

    func clear() throws {
        storage.removeAll()
    }
}
