import Foundation

enum PersistedReportOrigin: Int16 {
    case live = 0
    case nativeCrash = 1
    case outOfMemory = 2
}

protocol Repository {
    associatedtype Resource

    func save(_ resource: Resource) throws
    func save(_ resource: Resource, origin: PersistedReportOrigin) throws
    func getInitialSubmission(count: Int) throws -> [Resource]
    func claimInitialSubmission(_ resource: Resource) throws -> Bool
    func claimRetrySubmission(_ resource: Resource) throws -> Bool
    func markReadyForInitialSubmission(_ resource: Resource) throws
    func markReadyForRetry(_ resource: Resource) throws
    func markReadyForRetry(_ resource: Resource, incrementRetryCountWithLimit limit: Int) throws
    func markTerminalForDeletion(_ resource: Resource) throws
    func recoverStaleInFlightReportsOncePerProcess() throws
    func resetInFlightReports() throws
    func delete(_ resource: Resource) throws
    func getAll() throws -> [Resource]
    func get(sortDescriptors: [NSSortDescriptor]?, predicate: NSPredicate?, fetchLimit: Int?) throws -> [Resource]
    func incrementRetryCount(_ resource: Resource, limit: Int) throws
    func getLatest(count: Int) throws -> [Resource]
    func getOldest(count: Int) throws -> [Resource]
    func countResources() throws -> Int
    func clear() throws
}

extension Repository {
    func save(_ resource: Resource, origin: PersistedReportOrigin) throws {
        try save(resource)
    }
}
