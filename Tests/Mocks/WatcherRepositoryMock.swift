import Foundation
@testable import Backtrace

final class WatcherRepositoryMock<Resource: BacktraceReport> {
    class StoredResource {
        let resource: Resource
        var retryCount: Int = 0
        var state: PersistedReportState
        var deliveryOwner: String?

        init(_ resource: Resource,
             state: PersistedReportState = .readyForRetry) {
            self.resource = resource
            self.state = state
        }
    }
    var storage: [StoredResource] = []
    var deleteError: Error?
    var initialClaimDecision: ((Resource) -> Bool)?
    var competingInitialOwnerIsAlive = true
    private(set) var terminalIdentifiers = Set<UUID>()
    private let competingInitialOwner = "competing-initial-owner"

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
        if !competingInitialOwnerIsAlive {
            storage.filter {
                $0.state == .initialSubmissionInFlight &&
                    $0.deliveryOwner == competingInitialOwner
            }.forEach {
                $0.state = .readyForInitialSubmission
                $0.deliveryOwner = nil
            }
        }
        return Array(storage.filter { $0.state == .readyForInitialSubmission }
            .prefix(count)
            .map(\.resource))
    }

    func claimInitialSubmission(_ resource: Resource) throws -> Resource? {
        if let initialClaimDecision = initialClaimDecision,
           !initialClaimDecision(resource) {
            // Model the real race: this process fetched an eligible row,
            // then another process claimed it before this process's compare-and-swap transition.
            if let stored = storage.first(where: {
                $0.resource.identifier == resource.identifier &&
                    $0.state == .readyForInitialSubmission
            }) {
                stored.state = .initialSubmissionInFlight
                stored.deliveryOwner = competingInitialOwner
            }
            return nil
        }
        return claim(resource,
                     from: .readyForInitialSubmission,
                     to: .initialSubmissionInFlight,
                     owner: "local-owner")
    }

    func claimRetrySubmission(_ resource: Resource) throws -> Resource? {
        return claim(resource,
                     from: .readyForRetry,
                     to: .retryInFlight,
                     owner: "local-owner")
    }

    func releaseInitialClaim(_ resource: Resource) throws {
        _ = transition(resource,
                       from: .initialSubmissionInFlight,
                       to: .readyForInitialSubmission,
                       owner: nil)
    }

    func markReadyForRetry(_ resource: Resource) throws {
        guard let stored = storage.first(where: { $0.resource == resource }) else { return }
        stored.state = .readyForRetry
        stored.deliveryOwner = nil
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
        storage[index].deliveryOwner = nil
    }

    func resetInFlightReports() throws {
        storage.forEach {
            switch $0.state {
            case .initialSubmissionInFlight:
                $0.state = .readyForInitialSubmission
                $0.deliveryOwner = nil
            case .retryInFlight:
                $0.state = .readyForRetry
                $0.deliveryOwner = nil
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
        if let stored = storage.first(where: { $0.resource == resource }) {
            stored.state = .terminalAwaitingDeletion
            stored.deliveryOwner = nil
        }
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
        initialClaimDecision = nil
        competingInitialOwnerIsAlive = true
    }

    private var eligibleResources: [Resource] {
        return storage.filter { $0.state == .readyForRetry }.map(\.resource)
    }

    private func claim(_ resource: Resource,
                       from expectedState: PersistedReportState,
                       to targetState: PersistedReportState,
                       owner: String) -> Resource? {
        guard let stored = storage.first(where: {
            $0.resource.identifier == resource.identifier && $0.state == expectedState
        }) else {
            return nil
        }
        stored.state = targetState
        stored.deliveryOwner = owner
        return stored.resource
    }

    @discardableResult
    private func transition(_ resource: Resource,
                            from: PersistedReportState,
                            to: PersistedReportState,
                            owner: String? = nil) -> Bool {
        guard let stored = storage.first(where: { $0.resource == resource }),
              stored.state == from else { return false }
        stored.state = to
        stored.deliveryOwner = owner
        return true
    }
}
