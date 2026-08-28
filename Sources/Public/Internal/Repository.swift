import Foundation

protocol Repository {
    associatedtype Resource

    func save(_ resource: Resource) throws
    func getInitialSubmission(count: Int) throws -> [Resource]
    func claimInitialSubmission(_ resource: Resource) throws -> Bool
    func claimRetrySubmission(_ resource: Resource) throws -> Bool
    func releaseInitialClaim(_ resource: Resource) throws
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
