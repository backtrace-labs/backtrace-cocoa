import Foundation
@testable import Backtrace

final class WatcherRepositoryMock<Resource: BacktraceReport> {
    class StoredResource {
        let resource: Resource
        var retryCount: Int = 0
        var state: PersistedReportState

        init(_ resource: Resource,
             state: PersistedReportState = .readyForRetry) {
            self.resource = resource
            self.state = state
        }
    }
    var storage: [StoredResource] = []
    var deleteError: Error?
    private(set) var terminalIdentifiers = Set<UUID>()

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

    func storeInitial(_ resource: Resource) {
        storage.append(StoredResource(resource,
                                      state: .readyForInitialSubmission))
    }

    func getInitialSubmission(count: Int) throws -> [Resource] {
        return Array(storage.filter { $0.state == .readyForInitialSubmission }
            .prefix(count)
            .map(\.resource))
    }

    func claimInitialSubmission(_ resource: Resource) throws -> Bool {
        return transition(resource,
                          from: .readyForInitialSubmission,
                          to: .initialSubmissionInFlight)
    }

    func claimRetrySubmission(_ resource: Resource) throws -> Bool {
        return transition(resource, from: .readyForRetry, to: .retryInFlight)
    }

    func markReadyForInitialSubmission(_ resource: Resource) throws {
        _ = transition(resource,
                       from: .initialSubmissionInFlight,
                       to: .readyForInitialSubmission)
    }

    func markReadyForRetry(_ resource: Resource) throws {
        guard let stored = storage.first(where: { $0.resource == resource }) else { return }
        stored.state = .readyForRetry
    }

    func markReadyForRetry(_ resource: Resource,
                           incrementRetryCountWithLimit limit: Int) throws {
        guard let index = storage.firstIndex(where: { $0.resource == resource }),
              storage[index].state == .retryInFlight else { return }
        if storage[index].retryCount >= limit {
            if let deleteError = deleteError {
                throw deleteError
            }
            terminalIdentifiers.remove(resource.identifier)
            storage.remove(at: index)
            return
        }
        storage[index].retryCount += 1
        storage[index].state = .readyForRetry
    }

    func resetInFlightReports() throws {
        storage.forEach {
            switch $0.state {
            case .initialSubmissionInFlight:
                $0.state = .readyForInitialSubmission
            case .retryInFlight:
                $0.state = .readyForRetry
            default:
                break
            }
        }
    }

    func recoverStaleInFlightReportsOncePerProcess() throws {
        try resetInFlightReports()
    }

    func markTerminalForDeletion(_ resource: Resource) throws {
        terminalIdentifiers.insert(resource.identifier)
        storage.first(where: { $0.resource == resource })?.state = .terminalAwaitingDeletion
    }

    func delete(_ resource: Resource) throws {
        if let deleteError = deleteError {
            throw deleteError
        }
        if let idx = storage.firstIndex(where: { $0.resource == resource }) {
            storage.remove(at: idx)
        }
        terminalIdentifiers.remove(resource.identifier)
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
        return Array(eligibleResources.prefix(count))
    }

    func getOldest(count: Int) throws -> [Resource] {
        return Array(eligibleResources.suffix(count))
    }

    func countResources() throws -> Int {
        return storage.count
    }

    func clear() throws {
        storage.removeAll()
        terminalIdentifiers.removeAll()
        deleteError = nil
    }

    private var eligibleResources: [Resource] {
        return storage.filter { $0.state == .readyForRetry }.map(\.resource)
    }

    @discardableResult
    private func transition(_ resource: Resource,
                            from: PersistedReportState,
                            to: PersistedReportState) -> Bool {
        guard let stored = storage.first(where: { $0.resource == resource }),
              stored.state == from else { return false }
        stored.state = to
        return true
    }
}
