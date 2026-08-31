import Foundation
import CoreData
import Darwin

// This repository intentionally keeps its Core Data, file-ownership, and reconciliation transactions together so their lock ordering can be reviewed as one unit.
// swiftlint:disable file_length

private final class BacktraceResourceBundleToken: NSObject {}

private let maximumPendingCrashDeadLetters = 10

private enum RepositoryFileLockError: Error {
    case openFailed(Int32)
    case lockFailed(Int32)
}

private func setRepositoryFileLock(_ descriptor: Int32,
                                   command: Int32,
                                   type: Int16) -> Int32 {
    var fileLock = Darwin.flock()
    fileLock.l_type = type
    fileLock.l_whence = Int16(SEEK_SET)
    fileLock.l_start = 0
    fileLock.l_len = 0
    return Darwin.fcntl(descriptor, command, &fileLock)
}

/// An advisory lock shared by every process that opens the same repository database.
private final class RepositoryAdvisoryFileLock {
    private var descriptor: Int32
    private let localLock = NSRecursiveLock()
    private var lockDepth = 0

    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else {
            throw RepositoryFileLockError.openFailed(errno)
        }
    }

    deinit {
        close()
    }

    func close() {
        localLock.lock()
        defer { localLock.unlock() }
        guard descriptor >= 0 else { return }
        if lockDepth > 0 {
            _ = setRepositoryFileLock(descriptor, command: F_SETLK, type: Int16(F_UNLCK))
            lockDepth = 0
        }
        Darwin.close(descriptor)
        descriptor = -1
    }

    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        localLock.lock()
        defer { localLock.unlock() }
        if lockDepth == 0 {
            try lock(command: F_SETLKW)
        }
        lockDepth += 1
        defer {
            lockDepth -= 1
            if lockDepth == 0 {
                _ = setRepositoryFileLock(descriptor, command: F_SETLK, type: Int16(F_UNLCK))
            }
        }
        return try body()
    }

    private func lock(command: Int32) throws {
        guard descriptor >= 0 else {
            throw RepositoryFileLockError.openFailed(EBADF)
        }
        while setRepositoryFileLock(descriptor, command: command, type: Int16(F_WRLCK)) != 0 {
            guard errno == EINTR else {
                throw RepositoryFileLockError.lockFailed(errno)
            }
        }
    }
}

/// A live repository-generation lease used to distinguish abandoned in-flight rows
/// from reports actively owned by another process sharing the same SQLite store.
private final class RepositoryProcessLease {
    let token: String
    private let directoryUrl: URL
    private let leaseUrl: URL
    private let lifecycleLock = NSLock()
    private var descriptor: Int32

    init(databaseUrl: URL, token: String) throws {
        self.token = token
        directoryUrl = databaseUrl.deletingLastPathComponent()
            .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
            .appendingPathComponent("Leases", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryUrl,
                                                withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.none])
        leaseUrl = Self.leaseUrl(directoryUrl: directoryUrl, owner: token)
        descriptor = Darwin.open(leaseUrl.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else {
            throw RepositoryFileLockError.openFailed(errno)
        }
        guard setRepositoryFileLock(descriptor, command: F_SETLK, type: Int16(F_WRLCK)) == 0 else {
            let lockError = errno
            Darwin.close(descriptor)
            descriptor = -1
            try? FileManager.default.removeItem(at: leaseUrl)
            throw RepositoryFileLockError.lockFailed(lockError)
        }
        removeStaleLeaseFiles()
    }

    deinit {
        close()
    }

    func close() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard descriptor >= 0 else { return }
        _ = setRepositoryFileLock(descriptor, command: F_SETLK, type: Int16(F_UNLCK))
        Darwin.close(descriptor)
        descriptor = -1
        try? FileManager.default.removeItem(at: leaseUrl)
    }

    func isOwnerAlive(_ owner: String) -> Bool {
        if owner == token {
            lifecycleLock.lock()
            defer { lifecycleLock.unlock() }
            return descriptor >= 0
        }
        guard UUID(uuidString: owner) != nil else { return false }
        let leaseUrl = Self.leaseUrl(directoryUrl: directoryUrl, owner: owner)
        let candidateDescriptor = Darwin.open(leaseUrl.path, O_RDWR)
        guard candidateDescriptor >= 0 else {
            // Only a missing lease proves abandonment.
            // Permission, descriptor-exhaustion, and I/O failures leave liveness unknown, so defer recovery rather than risk a duplicate send.
            return errno != ENOENT
        }
        defer { Darwin.close(candidateDescriptor) }

        if setRepositoryFileLock(candidateDescriptor, command: F_SETLK, type: Int16(F_WRLCK)) == 0 {
            _ = setRepositoryFileLock(candidateDescriptor, command: F_SETLK, type: Int16(F_UNLCK))
            try? FileManager.default.removeItem(at: leaseUrl)
            return false
        }
        // Fail closed when liveness cannot be determined.
        // Replaying an actively owned report is more harmful than deferring recovery until a later process launch.
        return true
    }

    private func removeStaleLeaseFiles() {
        guard let leaseUrls = try? FileManager.default.contentsOfDirectory(at: directoryUrl,
                                                                          includingPropertiesForKeys: nil,
                                                                          options: [.skipsHiddenFiles]) else {
            return
        }
        for leaseUrl in leaseUrls where
            leaseUrl.pathExtension == "lock" &&
            leaseUrl.lastPathComponent != "\(token).lock" &&
            UUID(uuidString: leaseUrl.deletingPathExtension().lastPathComponent) != nil {
            let candidateDescriptor = Darwin.open(leaseUrl.path, O_RDWR)
            guard candidateDescriptor >= 0 else { continue }
            if setRepositoryFileLock(candidateDescriptor, command: F_SETLK, type: Int16(F_WRLCK)) == 0 {
                _ = setRepositoryFileLock(candidateDescriptor, command: F_SETLK, type: Int16(F_UNLCK))
                try? FileManager.default.removeItem(at: leaseUrl)
            }
            Darwin.close(candidateDescriptor)
        }
    }

    private static func leaseUrl(directoryUrl: URL, owner: String) -> URL {
        return directoryUrl.appendingPathComponent("\(owner).lock", isDirectory: false)
    }
}

private final class RepositorySharedState {
    let transactionLock = NSRecursiveLock()
    let advisoryLock: RepositoryAdvisoryFileLock
    let processLease: RepositoryProcessLease

    /// Access only while `transactionLock` is held.
    var staleRecoveryCompleted = false

    init(databaseUrl: URL) throws {
        let advisoryLock = try RepositoryAdvisoryFileLock(
            url: databaseUrl.appendingPathExtension("backtrace.lock")
        )
        self.advisoryLock = advisoryLock
        self.processLease = try advisoryLock.withExclusiveLock {
            try RepositoryProcessLease(databaseUrl: databaseUrl,
                                       token: UUID().uuidString)
        }
    }

    func retire() {
        processLease.close()
        advisoryLock.close()
    }
}

private final class WeakRepositorySharedState {
    weak var value: RepositorySharedState?

    init(_ value: RepositorySharedState) {
        self.value = value
    }
}

private final class RepositorySharedStateEntry {
    let state: RepositorySharedState
    var participantCount: Int

    init(state: RepositorySharedState, participantCount: Int) {
        self.state = state
        self.participantCount = participantCount
    }
}

private final class RepositorySharedStateHandle {
    let state: RepositorySharedState
    private let key: String
    private let releaseLock = NSLock()
    private var released = false

    init(key: String, state: RepositorySharedState) {
        self.key = key
        self.state = state
    }

    deinit {
        release()
    }

    func release() {
        releaseLock.lock()
        guard !released else {
            releaseLock.unlock()
            return
        }
        released = true
        releaseLock.unlock()
        RepositoryTransactionLockRegistry.shared.release(key: key, state: state)
    }
}

private final class RepositoryTransactionLockRegistry {
    static let shared = RepositoryTransactionLockRegistry()

    private let registryLock = NSLock()
    private var states = [String: RepositorySharedStateEntry]()

    private func key(for databaseUrl: URL) -> String {
        return databaseUrl.standardizedFileURL.path
    }

    func acquireSharedState(for databaseUrl: URL) throws -> RepositorySharedStateHandle {
        let key = key(for: databaseUrl)
        registryLock.lock()
        defer { registryLock.unlock() }
        if let entry = states[key] {
            entry.participantCount += 1
            return RepositorySharedStateHandle(key: key, state: entry.state)
        }
        // Keep the registry locked while creating the state,
        // concurrent repositories for one database cannot receive different in-process locks or delivery-owner tokens.
        let state = try RepositorySharedState(databaseUrl: databaseUrl)
        states[key] = RepositorySharedStateEntry(state: state, participantCount: 1)
        return RepositorySharedStateHandle(key: key, state: state)
    }

    fileprivate func release(key: String, state: RepositorySharedState) {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard let entry = states[key], entry.state === state else { return }
        entry.participantCount -= 1
        guard entry.participantCount == 0 else { return }
        states.removeValue(forKey: key)
        // Retire descriptors before another acquire can create a new generation.
        // This prevents a concurrently opened client from observing the old lease.
        state.retire()
    }

    var liveStateCountForTesting: Int {
        registryLock.lock()
        defer { registryLock.unlock() }
        return states.count
    }
}

/// Describes `PersistentStorable` Core Data
protocol PersistentStorable: AnyObject {
    associatedtype ManagedObjectType: NSManagedObject

    static var entityName: String { get }
    var identifier: UUID { get }
    var reportData: Data { get }
    var attachmentPaths: [String] { get set }
    var attributes: Attributes { get set }
    var pendingMetadataFilePaths: [String] { get set }
    /// Stable Core Data identity for a materialized persisted snapshot.
    /// Live reports have no identity until a later repository fetch.
    var persistedObjectURI: URL? { get }

    init(managedObject: ManagedObjectType, metadataDirectoryUrl: URL?) throws
}

enum PersistedReportState: Int16 {
    /// In-memory sentinel for an unknown non-null value read from the store.
    /// It is never persisted and deliberately fails closed for replay and eviction.
    case invalidPersistedState = -1
    case awaitingSourcePurge = 0
    case readyForInitialSubmission = 1
    case readyForRetry = 2
    case initialSubmissionInFlight = 3
    case retryInFlight = 4
    case terminalAwaitingDeletion = 5

    var blocksContentReplacement: Bool {
        switch self {
        case .invalidPersistedState,
             .initialSubmissionInFlight,
             .retryInFlight,
             .terminalAwaitingDeletion:
            return true
        case .awaitingSourcePurge, .readyForInitialSubmission, .readyForRetry:
            return false
        }
    }

    var evictionRank: Int? {
        switch self {
        case .terminalAwaitingDeletion:
            return 0
        case .readyForRetry:
            return 1
        case .invalidPersistedState,
             .awaitingSourcePurge,
             .readyForInitialSubmission,
             .initialSubmissionInFlight,
             .retryInFlight:
            // A pending native crash remains protected until it has entered the submission pipeline once.
            // After a transient initial attempt it becomes readyForRetry and ordinary capacity policy applies.
            return nil
        }
    }
}

enum PendingSaveOutcome: Equatable {
    case awaitingSourcePurge
    case alreadyOwned(PersistedReportState)
}

/// Persists `PersistentStorable` objects using Core Data
/// Manages concurrency by using a private-queue context and `performAndWaitThrowing` for all operations
final class PersistentRepository<Resource: PersistentStorable> {

    private struct EvictionCandidate {
        let object: Resource.ManagedObjectType
        let rank: Int
        let dateAdded: Date
        let identifier: UUID
    }

    private struct MaterializedPage {
        let resources: [Resource]
        /// Identifiers that no committed row still owns after corrupt rows are removed.
        /// A corrupt row's identifier is untrusted and can collide with a healthy row.
        let cleanupIdentifiers: [UUID]
        let removedObjectCount: Int
    }

    let backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings
    let url: URL
    let attachmentStore: RepositoryAttachmentStore
    let metadataDirectoryUrl: URL
    /// Explicitly released during native shutdown even though Unity retains the client for process lifetime.
    /// The participant-counted registry retires the advisory lock and lease synchronously when its final handle leaves.
    private var repositorySharedStateHandle: RepositorySharedStateHandle?
    private let deliveryOwnerToken: String
    private let deliveryOwnerIsAlive: (String) -> Bool
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false
    private let maintenanceQueue = DispatchQueue(label: "backtrace.repository.maintenance", qos: .utility)
    private let maintenanceStateLock = NSLock()
    private var capacityReconciliationScheduled = false
    private var capacityReconciliationRequested = false
    private let maintenanceRetryDelay: DispatchTimeInterval
    private let capacityReconciliationDidRun: ((PersistentRepository<Resource>) -> Void)?
    private let contextSave: (NSManagedObjectContext) throws -> Void
    private let databaseSize: (URL) throws -> Int

    private var pendingMetadataDirectoryUrl: URL {
        return metadataDirectoryUrl.appendingPathComponent("PendingMetadata", isDirectory: true)
    }

    private var deadLetterDirectoryUrl: URL {
        return metadataDirectoryUrl.appendingPathComponent("DeadLetters", isDirectory: true)
    }

    private var persistedRowDeadLetterDirectoryUrl: URL {
        return metadataDirectoryUrl.appendingPathComponent("PersistedRowDeadLetters", isDirectory: true)
    }

    // Keep initialization and its migration transaction together;
    // splitting the body would obscure the ordering between directory setup, the process lock, and Core Data loading.
    // swiftlint:disable function_body_length
    /// Creates a new `PersistentRepository`
    /// - Parameter settings: BacktraceDatabaseSettings
    /// - Throws: `RepositoryError`
    init(settings: BacktraceDatabaseSettings,
         startupReconciliation: ((PersistentRepository<Resource>) throws -> Void)? = nil,
         attachmentCopy: ((URL, URL) throws -> Void)? = nil,
         attachmentResourceValues: ((URL) throws -> URLResourceValues)? = nil,
         databaseSize: @escaping (URL) throws -> Int = { try BacktraceFileManager.sizeOfFile(at: $0) },
         contextSave: @escaping (NSManagedObjectContext) throws -> Void = { try $0.save() },
         maintenanceRetryDelay: DispatchTimeInterval = .seconds(1),
         capacityReconciliationDidRun: ((PersistentRepository<Resource>) -> Void)? = nil,
         storeDirectoryUrl: URL? = nil,
         deliveryOwnerToken: String? = nil,
         deliveryOwnerIsAlive: ((String) -> Bool)? = nil) throws {
        let resolvedStoreDirectoryUrl: URL
        if let requestedStoreDirectoryUrl = storeDirectoryUrl {
            resolvedStoreDirectoryUrl = requestedStoreDirectoryUrl
        } else if #available(iOS 10.0, tvOS 10.0, macOS 10.12, *) {
            resolvedStoreDirectoryUrl = NSPersistentContainer.defaultDirectoryURL()
        } else if let applicationSupportUrl = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).last {
            resolvedStoreDirectoryUrl = applicationSupportUrl
        } else {
            throw RepositoryError.persistentRepositoryInitError(details: "Unable to resolve document directory")
        }
        let resolvedDatabaseUrl = resolvedStoreDirectoryUrl
            .appendingPathComponent("Model.sqlite", isDirectory: false)
            .standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: resolvedStoreDirectoryUrl,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        } catch {
            throw RepositoryError.persistentRepositoryInitError(
                details: "The retry database directory could not be created."
            )
        }
        let sharedStateHandle: RepositorySharedStateHandle
        do {
            sharedStateHandle = try RepositoryTransactionLockRegistry.shared
                .acquireSharedState(for: resolvedDatabaseUrl)
        } catch {
            throw RepositoryError.persistentRepositoryInitError(
                details: "The retry database process lock could not be prepared."
            )
        }
        let sharedState = sharedStateHandle.state
        self.repositorySharedStateHandle = sharedStateHandle
        let sharedAdvisoryLock = sharedState.advisoryLock
        let processLease = sharedState.processLease
        let weakSharedState = WeakRepositorySharedState(sharedState)
        self.deliveryOwnerToken = deliveryOwnerToken ?? processLease.token
        self.deliveryOwnerIsAlive = deliveryOwnerIsAlive ?? { owner in
            // Unknown liveness must fail closed. During an admitted transaction its local shared-state snapshot keeps this weak value alive. 
            weakSharedState.value?.processLease.isOwnerAlive(owner) ?? true
        }
        self.settings = settings
        self.databaseSize = databaseSize
        self.contextSave = contextSave
        self.maintenanceRetryDelay = maintenanceRetryDelay
        self.capacityReconciliationDidRun = capacityReconciliationDidRun
        let momdName = "Model"
        guard let modelDirectoryURL = Self.resolveModelUrl(modelName: momdName) else {
            throw RepositoryError
                .persistentRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
        }
        // Load the destination schema explicitly instead of trusting VersionInfo.plist's current version.
        // PLCrashReporter also ships a generic Model.xcdatamodeld;
        // some Xcode test builds temporarily synchronize that version group's v1 selection into this source tree while preparing CocoaPods test dependencies.
        // Both versions remain packaged for lightweight migration, but repository state must always use the row-backed V2 schema.
        let currentModelURL = modelDirectoryURL.appendingPathComponent("ModelV2.mom", isDirectory: false)
        BacktraceLogger.debug("Resolved Core Data model at: \(currentModelURL.path)")
        guard let managedObjectModel = NSManagedObjectModel(contentsOf: currentModelURL) else {
            throw RepositoryError.persistentRepositoryInitError(
                details: "The packaged retry database ModelV2 schema could not be loaded."
            )
        }
        if #available(iOS 10.0, tvOS 10.0, macOS 10.12, *) {
            let persistentContainer = NSPersistentContainer(name: momdName, managedObjectModel: managedObjectModel)
            let storeUrl = resolvedDatabaseUrl
            let storeDescription = NSPersistentStoreDescription(url: storeUrl)
            storeDescription.type = NSSQLiteStoreType
            storeDescription.shouldMigrateStoreAutomatically = true
            storeDescription.shouldInferMappingModelAutomatically = true
            persistentContainer.persistentStoreDescriptions = [storeDescription]
            let dispatch = DispatchSemaphore(value: 0)
            var loadPersistentStoresError: Error?
            var url: URL?
            do {
                // Store discovery may perform a lightweight migration.
                // Serialize that work with other processes before any context is allowed to read or mutate delivery rows.
                try sharedAdvisoryLock.withExclusiveLock {
                    persistentContainer.loadPersistentStores { (storeDescription, error) in
                        BacktraceLogger.debug("Loaded persistent stores, store description: \(storeDescription)")
                        loadPersistentStoresError = error
                        url = storeDescription.url
                        dispatch.signal()
                    }
                    dispatch.wait()
                }
            } catch {
                throw RepositoryError.persistentRepositoryInitError(
                    details: "The retry database could not be locked for migration."
                )
            }
            if let error = loadPersistentStoresError {
                throw RepositoryError.persistentRepositoryInitError(
                    details: "The retry database could not be loaded (\(String(describing: type(of: error))))."
                )
            }
            guard let storeUrl = url else {
                throw RepositoryError.persistentRepositoryInitError(
                    details: "The retry database loaded without a persistent store location."
                )
            }
            backgroundContext = persistentContainer.newBackgroundContext()
            self.url = storeUrl
        } else {
            let psc = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
            let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            managedObjectContext.persistentStoreCoordinator = psc
            let storeDir = resolvedStoreDirectoryUrl
            let storeURL = resolvedDatabaseUrl
            do {
                try FileManager.default.createDirectory(at: storeDir,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
                _ = try sharedAdvisoryLock.withExclusiveLock {
                    try psc.addPersistentStore(ofType: NSSQLiteStoreType,
                                               configurationName: nil,
                                               at: storeURL,
                                               options: [
                                                NSMigratePersistentStoresAutomaticallyOption: true,
                                                NSInferMappingModelAutomaticallyOption: true
                                               ])
                }
            } catch {
                throw RepositoryError.persistentRepositoryInitError(
                    details: "The retry database could not be prepared or loaded."
                )
            }
            BacktraceLogger.debug("Loaded persistent stores, sore description: \(psc.persistentStores)")
            backgroundContext = managedObjectContext
            url = storeURL
        }
        do {
            try BacktraceFileManager.excludeFromBackup(url)
            self.attachmentStore = try RepositoryAttachmentStore(databaseUrl: url,
                                                                 copyItem: attachmentCopy,
                                                                 regularFileResourceValues: attachmentResourceValues)
            self.metadataDirectoryUrl = url.deletingLastPathComponent()
                .appendingPathComponent("BacktraceReportMetadata", isDirectory: true)
                .standardizedFileURL
            try FileManager.default.createDirectory(at: metadataDirectoryUrl,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.none])
            try? BacktraceFileManager.excludeFromBackup(metadataDirectoryUrl)
        } catch {
            throw RepositoryError.persistentRepositoryInitError(
                details: "Retry repository file storage is unavailable (\(String(describing: type(of: error))))."
            )
        }
        do {
            try initializeMigratedDeliveryStates()
        } catch {
            throw RepositoryError.persistentRepositoryInitError(
                details: "Retry repository delivery state could not be migrated safely."
            )
        }
        performStartupReconciliation(startupReconciliation)
    }
    // swiftlint:enable function_body_length

    /// Lightweight migration leaves the new optional state unset on rows created by released SDKs.
    /// Those rows were all ordinary retry work, initialize them directly,
    /// without depending on the temporary global sidecar used only by unreleased development builds.
    private func initializeMigratedDeliveryStates() throws {
        try withTransaction {
            try backgroundContext.performAndWaitThrowing {
                do {
                    for managedObject in try _getResourcesLocked()
                    where managedObject.value(forKey: "deliveryStateRaw") == nil {
                        setDeliveryStateLocked(.readyForRetry, on: managedObject)
                    }
                    if backgroundContext.hasChanges {
                        try contextSave(backgroundContext)
                    }
                } catch {
                    backgroundContext.rollback()
                    throw error
                }
            }
        }
    }

    private func performStartupReconciliation(
        _ startupReconciliation: ((PersistentRepository<Resource>) throws -> Void)?
    ) {
        if let startupReconciliation = startupReconciliation {
            do {
                try startupReconciliation(self)
            } catch {
                BacktraceLogger.warning("Repository startup cleanup was deferred.")
                maintenanceQueue.asyncAfter(deadline: .now() + maintenanceRetryDelay) { [weak self] in
                    self?.reconcileStorageBestEffort(scheduleRetry: false)
                }
            }
        } else {
            reconcileStorageBestEffort(scheduleRetry: true)
        }
    }

    static func resolveModelUrl(modelName: String = "Model") -> URL? {
#if SWIFT_PACKAGE
        let moduleUrl = Bundle.module.url(forResource: modelName, withExtension: "momd")
        BacktraceLogger.debug("Core Data model candidate (SwiftPM direct): \(moduleUrl?.path ?? "missing")")
        return selectCompatibleModelUrl([moduleUrl])
#else
        let sdkBundle = Bundle(for: BacktraceResourceBundleToken.self)
        let mainBundle = Bundle.main
        var candidates = [URL?]()

        // When the SDK is a framework or plug-in bundle, its own resources are authoritative.
        // When statically linked, Bundle(for:) is Bundle.main and direct resources may belong to the host app,
        // prefer the named Backtrace resource bundle before the generic fallback.
        if sdkBundle.bundleURL != mainBundle.bundleURL {
            candidates.append(sdkBundle.url(forResource: modelName, withExtension: "momd"))
            candidates.append(nestedModelUrl(in: sdkBundle, modelName: modelName))
        }
        candidates.append(nestedModelUrl(in: mainBundle, modelName: modelName))
        candidates.append(mainBundle.url(forResource: modelName, withExtension: "momd"))

        return selectCompatibleModelUrl(candidates)
#endif
    }

    internal static var liveSharedStateCountForTesting: Int {
        return RepositoryTransactionLockRegistry.shared.liveStateCountForTesting
    }

    internal var sharedStateIdentifierForTesting: ObjectIdentifier? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return repositorySharedStateHandle.map { ObjectIdentifier($0.state) }
    }

    internal var deliveryOwnerTokenForTesting: String {
        return deliveryOwnerToken
    }

    private static func nestedModelUrl(in bundle: Bundle, modelName: String) -> URL? {
        return bundle.url(forResource: "BacktraceResources", withExtension: "bundle")
            .flatMap { Bundle(url: $0) }?
            .url(forResource: modelName, withExtension: "momd")
    }

    /// Rejects a host application's unrelated generic Model.momd and continues searching for the SDK schema.
    /// The repository always loads ModelV2 explicitly from the returned directory.
    static func selectCompatibleModelUrl(_ candidates: [URL?]) -> URL? {
        for candidate in candidates.compactMap({ $0 }) {
            let currentModelUrl = candidate.appendingPathComponent("ModelV2.mom", isDirectory: false)
            BacktraceLogger.debug("Core Data model candidate: \(candidate.path)")
            if FileManager.default.fileExists(atPath: currentModelUrl.path) {
                return candidate
            }
            BacktraceLogger.warning("Ignored a Core Data model candidate without ModelV2.mom.")
        }

        BacktraceLogger.error("Unable to resolve a compatible Model.momd from Backtrace SDK resources")
        return nil
    }

}

// MARK: - Repository
extension PersistentRepository: Repository {
    
    /// Saves a new resource to Core Data
    /// - Parameter resource: Resource to save
    /// Throws:
    ///   - `RepositoryError.canNotCreateEntityDescription` if the entity cannot be found
    ///   - Any Core Data error that occurs during the save
    func save(_ resource: Resource) throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            _ = try _save(resource,
                          isPendingCrash: false,
                          initialState: .readyForRetry)
        }
    }

    /// Durably saves a pending crash before its PLCrashReporter source may be purged.
    ///
    /// The report is initially ineligible for submission. It becomes eligible only after PLCrashReporter confirms
    /// that its source has been purged, preventing replay from submitting the same source more than once.
    @discardableResult
    func savePending(_ resource: Resource) throws -> PendingSaveOutcome {
        return try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            let state = try _save(resource,
                                  isPendingCrash: true,
                                  initialState: .awaitingSourcePurge)
            return state == .awaitingSourcePurge
                ? .awaitingSourcePurge
                : .alreadyOwned(state)
        }
    }

    // The save transaction keeps its file rollback and Core Data rollback paths adjacent.
    // swiftlint:disable:next function_body_length
    private func _save(_ resource: Resource,
                       isPendingCrash: Bool,
                       initialState: PersistedReportState) throws -> PersistedReportState {
        let existingSnapshot: (state: PersistedReportState, attachmentPaths: [String])? =
            try backgroundContext.performAndWaitThrowing {
                let predicate = NSPredicate(format: "hashProperty == %@", resource.identifier.uuidString)
                guard let managedObject = try _getResourcesLocked(predicate: predicate, fetchLimit: 1).first else {
                    return nil
                }
                return (
                    state: deliveryStateLocked(managedObject),
                    attachmentPaths: managedObject.value(forKey: "attachmentPaths") as? [String] ?? []
                )
            }
        if let snapshot = existingSnapshot, snapshot.state.blocksContentReplacement {
            // A duplicate ingestion may observe the same deterministic report while another process owns its delivery.
            // Do not revoke that claim or replace files underneath request construction.
            // Terminal rows are immutable for the same reason.
            resource.attachmentPaths = snapshot.attachmentPaths
            return snapshot.state
        }

        if isPendingCrash {
            preservePendingMetadataFilesLocked(resource)
        }
        let existingAttachmentPaths = existingSnapshot?.attachmentPaths ?? []
        let attributesConfig = try AttributesStorage.AttributesConfig(
            fileName: resource.identifier.uuidString,
            directoryUrl: metadataDirectoryUrl
        )
        let previousAttributesData: Data?
        if FileManager.default.fileExists(atPath: attributesConfig.fileUrl.path) {
            previousAttributesData = try Data(contentsOf: attributesConfig.fileUrl)
        } else {
            previousAttributesData = nil
        }
        let candidateAttachments = try attachmentStore.store(resource.attachmentPaths,
                                                              reportIdentifier: resource.identifier,
                                                              skipsUnreadableSources: isPendingCrash)
        if isPendingCrash && !candidateAttachments.isComplete {
            let missingCount = max(1, resource.attachmentPaths.count - candidateAttachments.paths.count)
            resource.attributes[BacktracePendingCrashMetadata.missingAttachmentsKey] = missingCount
        }
        let durableExistingAttachmentPaths = existingAttachmentPaths.filter { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return attachmentStore.contains(url) && FileManager.default.fileExists(atPath: url.path)
        }
        let shouldPreserveExistingAttachments = !durableExistingAttachmentPaths.isEmpty &&
            (resource.attachmentPaths.isEmpty || !candidateAttachments.isComplete)
        let storedAttachments: RepositoryAttachmentStore.StoredAttachments
        if shouldPreserveExistingAttachments {
            attachmentStore.rollback(candidateAttachments)
            storedAttachments = RepositoryAttachmentStore.StoredAttachments(
                paths: durableExistingAttachmentPaths,
                generationUrl: nil,
                isComplete: true
            )
        } else {
            storedAttachments = candidateAttachments
        }

        var persistedAttributes = (try? AttributesStorage.retrieve(
            fileName: resource.identifier.uuidString,
            directoryUrl: metadataDirectoryUrl
        )) ?? [:]
        persistedAttributes += resource.attributes
        if isPendingCrash {
            let sanitized = propertyListSafeAttributes(persistedAttributes)
            persistedAttributes = sanitized.attributes
            if sanitized.removedValueCount > 0 {
                persistedAttributes[BacktracePendingCrashMetadata.invalidAttributeValuesKey] =
                    sanitized.removedValueCount
            }
        }
        do {
            try AttributesStorage.store(persistedAttributes,
                                        fileName: resource.identifier.uuidString,
                                        directoryUrl: metadataDirectoryUrl)
        } catch {
            attachmentStore.rollback(storedAttachments)
            restoreAttributes(previousAttributesData, config: attributesConfig)
            throw error
        }

        let evictedIdentifiers: [UUID]
        do {
            evictedIdentifiers = try backgroundContext.performAndWaitThrowing {
                do {
                    let predicate = NSPredicate(format: "hashProperty == %@", resource.identifier.uuidString)
                    let existingObject = try _getResourcesLocked(predicate: predicate, fetchLimit: 1).first
                    var identifiersToClean = [UUID]()

                    let managedObject: NSManagedObject
                    if let existingObject = existingObject {
                        managedObject = existingObject
                    } else {
                        identifiersToClean = try _removeOldestRecordIfNeededLocked()
                        guard let entity = NSEntityDescription.entity(forEntityName: Resource.entityName,
                                                                      in: backgroundContext) else {
                            throw RepositoryError.canNotCreateEntityDescription
                        }
                        managedObject = NSManagedObject(entity: entity, insertInto: backgroundContext)
                        managedObject.setValue(resource.identifier.uuidString, forKey: "hashProperty")
                        managedObject.setValue(Date(), forKey: "dateAdded")
                        managedObject.setValue(0, forKey: "retryCount")
                    }

                    managedObject.setValue(resource.reportData, forKey: "reportData")
                    managedObject.setValue(storedAttachments.paths, forKey: "attachmentPaths")
                    if existingObject == nil {
                        setDeliveryStateLocked(initialState, on: managedObject)
                        setDeliveryOwnerLocked(nil, on: managedObject)
                    }
                    try contextSave(backgroundContext)
                    return identifiersToClean
                } catch {
                    // File artifacts are rolled back below.
                    // Reset every staged mutation so an unrelated later save cannot commit a failed insertion, update, or eviction.
                    backgroundContext.rollback()
                    throw error
                }
            }
        } catch {
            attachmentStore.rollback(storedAttachments)
            restoreAttributes(previousAttributesData, config: attributesConfig)
            throw error
        }

        resource.attachmentPaths = storedAttachments.paths
        cleanupResources(identifiers: evictedIdentifiers)
        if existingSnapshot != nil,
           existingAttachmentPaths != storedAttachments.paths {
            // Replacing a row changes the only durable attachment reference but does not create an eviction identifier.
            // Reconcile synchronously while the repository transaction is still held,
            // superseded immutable generations do not accumulate under unlimited capacity.
            reconcileAttachmentsFromCommittedRowsBestEffort()
        }
        // Capacity must observe the committed payload and attachment generation
        // for both inserts and identifier-based replacements.
        // Protected rows may temporarily exceed configured capacity until they become safely evictable.
        scheduleCapacityReconciliation()
        return existingSnapshot?.state ?? initialState
    }

    /// Promotes a durably persisted pending report only after its PLCrashReporter source is gone.
    func promoteAfterSourcePurge(_ resource: Resource) throws {
        try transition(resource,
                       from: [.awaitingSourcePurge],
                       to: .readyForInitialSubmission)
    }

    /// Releases a claimed initial delivery when no transport attempt was admitted.
    func releaseInitialClaim(_ resource: Resource) throws {
        try transition(resource,
                       from: [.initialSubmissionInFlight],
                       to: .readyForInitialSubmission)
    }

    /// A process may terminate after source purge but before the eligibility transition is written.
    /// When there is no matching pending PLCrashReporter source, those rows are safe to replay.
    func markAwaitingReportsReady(except identifier: UUID? = nil) throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            let preservedIdentifier = identifier?.uuidString
            let didPromote = try backgroundContext.performAndWaitThrowing {
                do {
                    var didPromote = false
                    for managedObject in try _getResourcesLocked() {
                        guard managedObject.value(forKey: "hashProperty") as? String != preservedIdentifier,
                              deliveryStateLocked(managedObject) == .awaitingSourcePurge else { continue }
                        setDeliveryStateLocked(.readyForInitialSubmission, on: managedObject)
                        setDeliveryOwnerLocked(nil, on: managedObject)
                        didPromote = true
                    }
                    if didPromote {
                        try contextSave(backgroundContext)
                    }
                    return didPromote
                } catch {
                    backgroundContext.rollback()
                    throw error
                }
            }
            if didPromote {
                scheduleCapacityReconciliation()
            }
        }
    }

    func persistedState(for resource: Resource) throws -> PersistedReportState {
        return try withTransaction {
            return try backgroundContext.performAndWaitThrowing {
                guard let managedObject = try managedObjectLocked(for: resource) else {
                    throw RepositoryError.resourceNotFound
                }
                return deliveryStateLocked(managedObject)
            }
        }
    }

    func persistedDeliveryOwner(for resource: Resource) throws -> String? {
        return try withTransaction {
            try backgroundContext.performAndWaitThrowing {
                guard let managedObject = try managedObjectLocked(for: resource) else {
                    throw RepositoryError.resourceNotFound
                }
                return managedObject.value(forKey: "deliveryOwner") as? String
            }
        }
    }

    func getInitialSubmission(count: Int) throws -> [Resource] {
        let page = try withTransaction {
            // A process that owned a claim may exit after this client starts.
            // Recheck leases at every submission fetch so the surviving client can eventually resume that row.
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            let page = try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
                let initial = try _getResourcesLocked(sortDescriptors: sortDescriptors).filter {
                    deliveryStateLocked($0) == .readyForInitialSubmission
                }
                return try materializeEligiblePageLocked(initial, limit: count)
            }
            cleanupResources(identifiers: page.cleanupIdentifiers)
            return page
        }
        reconcileOrphansAfterCorruptRows(page)
        return page.resources
    }

    func claimInitialSubmission(_ resource: Resource) throws -> Resource? {
        return try claim(resource,
                         expectedState: .readyForInitialSubmission,
                         inFlightState: .initialSubmissionInFlight)
    }

    func claimRetrySubmission(_ resource: Resource) throws -> Resource? {
        return try claim(resource,
                         expectedState: .readyForRetry,
                         inFlightState: .retryInFlight)
    }

    func markReadyForRetry(_ resource: Resource) throws {
        try transition(resource,
                       from: [.initialSubmissionInFlight, .retryInFlight],
                       to: .readyForRetry)
    }

    /// Completes a retry attempt and applies retry-limit accounting in the same store transaction.
    /// Keeping the row in `retryInFlight` until the count update or deletion commits prevents a second repository instance from claiming a row that the first instance is about to evict.
    func markReadyForRetry(_ resource: Resource,
                           incrementRetryCountWithLimit limit: Int) throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            let result: (deletedIdentifiers: [UUID], becameEvictable: Bool) =
                try backgroundContext.performAndWaitThrowing {
                    guard let managedObject = try managedObjectLocked(for: resource) else {
                        throw RepositoryError.resourceNotFound
                    }
                    guard deliveryStateLocked(managedObject) == .retryInFlight else {
                        return ([], false)
                    }
                    guard let currentRetryCount = managedObject.value(forKey: "retryCount") as? Int else {
                        throw RepositoryError.resourceNotFound
                    }

                    do {
                        if currentRetryCount >= limit {
                            return (try _deleteLocked([managedObject]), false)
                        }
                        setDeliveryStateLocked(.readyForRetry, on: managedObject)
                        setDeliveryOwnerLocked(nil, on: managedObject)
                        managedObject.setValue(currentRetryCount + 1, forKey: "retryCount")
                        managedObject.setValue(resource.reportData, forKey: "reportData")
                        try _saveContextLocked()
                        return ([], true)
                    } catch {
                        backgroundContext.rollback()
                        throw error
                    }
                }
            cleanupResources(identifiers: result.deletedIdentifiers)
            if result.becameEvictable {
                scheduleCapacityReconciliation()
            }
        }
    }

    /// Durably excludes a terminally handled row from replay before attempting its cleanup.
    func markTerminalForDeletion(_ resource: Resource) throws {
        try transition(resource,
                       from: nil,
                       to: .terminalAwaitingDeletion)
    }

    /// Recovers abandoned claims once per live shared-state generation.
    /// A second live client must not rewind a claim owned by the first client, while reopening
    /// after the final repository release must be able to recover claims owned by the old lease.
    func recoverStaleInFlightReportsOncePerProcess() throws {
        try withSharedStateTransaction { sharedState in
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            guard !sharedState.staleRecoveryCompleted else { return }
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            // Mark only after the Core Data transaction commits.
            // A failed first client therefore leaves recovery available to a later client in the same process.
            sharedState.staleRecoveryCompleted = true
        }
    }

    /// Explicit recovery hook retained for tests and manual repository repair.
    func resetInFlightReports() throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            try resetInFlightReportsLocked(onlyAbandonedOwners: false)
        }
    }

    private func resetInFlightReportsLocked(onlyAbandonedOwners: Bool) throws {
        var recoveredClaim = false
        try backgroundContext.performAndWaitThrowing {
            do {
                for managedObject in try _getResourcesLocked() {
                    let state = deliveryStateLocked(managedObject)
                    guard state == .initialSubmissionInFlight || state == .retryInFlight else {
                        continue
                    }
                    if onlyAbandonedOwners,
                       let owner = managedObject.value(forKey: "deliveryOwner") as? String,
                       deliveryOwnerIsAlive(owner) {
                        continue
                    }
                    switch state {
                    case .initialSubmissionInFlight:
                        setDeliveryStateLocked(.readyForInitialSubmission, on: managedObject)
                    case .retryInFlight:
                        setDeliveryStateLocked(.readyForRetry, on: managedObject)
                    default:
                        continue
                    }
                    setDeliveryOwnerLocked(nil, on: managedObject)
                    recoveredClaim = true
                }
                if backgroundContext.hasChanges {
                    try contextSave(backgroundContext)
                }
            } catch {
                backgroundContext.rollback()
                throw error
            }
        }
        if recoveredClaim {
            scheduleCapacityReconciliation()
        }
    }
    
    /// Deletes a resource from Core Data
    /// - Parameter resource: Resource to delete
    /// - Throws: Any error from fetching or deleting the records
    func delete(_ resource: Resource) throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            let deletedIdentifiers = try backgroundContext.performAndWaitThrowing {
                let fetchRequestResults: [Resource.ManagedObjectType]
                if resource.persistedObjectURI != nil {
                    // Submission snapshots own one exact durable row.
                    // Never let a colliding identifier broaden terminal cleanup to another row.
                    fetchRequestResults = try managedObjectLocked(for: resource).map { [$0] } ?? []
                } else {
                    // Preserve the legacy public delete behavior for live resources
                    // that have not been materialized from this repository.
                    let predicate = NSPredicate(
                        format: "hashProperty==%@",
                        resource.identifier.uuidString
                    )
                    fetchRequestResults = try _getResourcesLocked(
                        predicate: predicate,
                        fetchLimit: 100
                    )
                }
                return try _deleteLocked(fetchRequestResults)
            }
            cleanupResources(identifiers: deletedIdentifiers)
        }
    }
    
    /// Fetches all stored resources from the database
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getAll() throws -> [Resource] {
        return try withTransaction {
            try backgroundContext.performAndWaitThrowing {
                let resources = try _getResourcesLocked()
                return try resources.map { try Resource(managedObject: $0,
                                                        metadataDirectoryUrl: metadataDirectoryUrl) }
            }
        }
    }
    
    /// Fetches resources matching optional sort, predicate, and limit criteria
    /// - Parameters:
    ///   - sortDescriptors: [NSSortDescriptor]
    ///   - predicate: NSPredicate?
    ///   - fetchLimit: Int?
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization.
    func get(sortDescriptors: [NSSortDescriptor]? = nil,
             predicate: NSPredicate? = nil,
             fetchLimit: Int? = nil) throws -> [Resource] {
        return try withTransaction {
            try backgroundContext.performAndWaitThrowing {
                let resources = try _getResourcesLocked(sortDescriptors: sortDescriptors,
                                                        predicate: predicate,
                                                        fetchLimit: fetchLimit)
                return try resources.prefix(fetchLimit ?? resources.count).map {
                    try Resource(managedObject: $0, metadataDirectoryUrl: metadataDirectoryUrl)
                }
            }
        }
    }
    
    /// Fetches the newest (by `dateAdded`) resources
    /// - Parameter count: Int : Default`1`
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getLatest(count: Int = 1) throws -> [Resource] {
        let page = try withTransaction {
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            let page = try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
                let latest = submissionEligibleResourcesLocked(
                    try _getResourcesLocked(sortDescriptors: sortDescriptors)
                )
                return try materializeEligiblePageLocked(latest, limit: count)
            }
            cleanupResources(identifiers: page.cleanupIdentifiers)
            return page
        }
        reconcileOrphansAfterCorruptRows(page)
        return page.resources
    }
    
    /// Fetches the oldest (by `dateAdded`) resources
    /// - Parameter count: Int : Default`1`
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getOldest(count: Int = 1) throws -> [Resource] {
        let page = try withTransaction {
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            let page = try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
                let oldest = submissionEligibleResourcesLocked(
                    try _getResourcesLocked(sortDescriptors: sortDescriptors)
                )
                return try materializeEligiblePageLocked(oldest, limit: count)
            }
            cleanupResources(identifiers: page.cleanupIdentifiers)
            return page
        }
        reconcileOrphansAfterCorruptRows(page)
        return page.resources
    }
    
    /// Increments the retry count for a resource. If the count reaches limit, removes the resource from the database.
    /// - Parameters:
    ///   - resource: Resource
    ///   - limit: Int
    ///   - Throws:
    ///     - `RepositoryError.resourceNotFound` if the resource cannot be fetched
    ///     - Any error from saving or deleting in Core Data
    func incrementRetryCount(_ resource: Resource, limit: Int) throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            let deletedIdentifiers = try backgroundContext.performAndWaitThrowing {
                let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
                let fetchRequestResults = try _getResourcesLocked(predicate: predicate, fetchLimit: 1)

                guard let fetchedResult = fetchRequestResults.first,
                      let currentRetryCount: Int = fetchedResult.value(forKey: "retryCount") as? Int else {
                    throw RepositoryError.resourceNotFound
                }
                // if exceeds limit, remove from db, otherwise just increment retryCount property
                if currentRetryCount >= limit {
                    return try _deleteLocked([fetchedResult])
                } else {
                    // increment number of retires
                    fetchedResult.setValue(currentRetryCount + 1, forKey: "retryCount")
                    // update report data (could be modified)
                    fetchedResult.setValue(resource.reportData, forKey: "reportData")
                    try _saveContextLocked()
                    return []
                }
            }
            cleanupResources(identifiers: deletedIdentifiers)
        }
    }
    
    /// Deletes all stored resources
    /// - Throws: Any error from fetching or deleting the records
    func clear() throws {
        try withTransaction {
            let deletedIdentifiers = try backgroundContext.performAndWaitThrowing {
                let managedObjects = try _getResourcesLocked()
                return try _deleteLocked(managedObjects)
            }
            cleanupResources(identifiers: deletedIdentifiers)
        }
    }
    
    ///  Returns the total count of resources in the database
    /// - Returns: Int: The number of resources
    func countResources() throws -> Int {
        try withTransaction {
            try backgroundContext.performAndWaitThrowing {
                try _countResourcesLocked()
            }
        }
    }
    
    // MARK: - Private Locked Helpers
    // Must be called only inside performAndWait{}
    
    /// Convenience method for fetching objects from the context
    /// Must be called only inside a `performAndWaitThrowing` block
    ///
    /// - Parameters:
    ///     - Parameter sortDescriptors:[NSSortDescriptor]?
    ///     - Parameter predicate:NSPredicate?
    ///     - Parameter fetchLimit:Int?
    /// - Returns: [Resource.ManagedObjectType]
    /// - Throws: Any error from `fetch(_:)`.
    private func _getResourcesLocked(sortDescriptors: [NSSortDescriptor]? = nil,
                                     predicate: NSPredicate? = nil,
                                     fetchLimit: Int? = nil) throws -> [Resource.ManagedObjectType] {
        let request = NSFetchRequest<Resource.ManagedObjectType>(entityName: Resource.entityName)
        request.returnsObjectsAsFaults = false
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        request.sortDescriptors = sortDescriptors
        request.predicate = predicate
        return try backgroundContext.fetch(request)
    }

    private func managedObjectLocked(for resource: Resource) throws -> Resource.ManagedObjectType? {
        if let objectURI = resource.persistedObjectURI {
            // A fetched resource must keep targeting the exact row that produced its snapshot.
            // Falling back to a non-unique hash could claim or finalize a different row after identifier corruption.
            guard let coordinator = backgroundContext.persistentStoreCoordinator,
                  let objectID = coordinator.managedObjectID(forURIRepresentation: objectURI),
                  let managedObject = try backgroundContext.existingObject(with: objectID)
                    as? Resource.ManagedObjectType,
                  let persistedIdentifierString = managedObject.value(forKey: "hashProperty") as? String,
                  UUID(uuidString: persistedIdentifierString) == resource.identifier else {
                return nil
            }
            return managedObject
        }
        let predicate = NSPredicate(format: "hashProperty == %@", resource.identifier.uuidString)
        return try _getResourcesLocked(predicate: predicate, fetchLimit: 1).first
    }

    private func deliveryStateLocked(_ managedObject: NSManagedObject) -> PersistedReportState {
        guard let value = managedObject.value(forKey: "deliveryStateRaw") as? NSNumber else {
            // Rows produced before ModelV2 are ordinary retry rows.
            return .readyForRetry
        }
        return PersistedReportState(rawValue: value.int16Value) ?? .invalidPersistedState
    }

    private func setDeliveryStateLocked(_ state: PersistedReportState, on managedObject: NSManagedObject) {
        managedObject.setValue(NSNumber(value: state.rawValue), forKey: "deliveryStateRaw")
    }

    private func setDeliveryOwnerLocked(_ owner: String?, on managedObject: NSManagedObject) {
        managedObject.setValue(owner, forKey: "deliveryOwner")
    }

    private func claim(_ resource: Resource,
                       expectedState: PersistedReportState,
                       inFlightState: PersistedReportState) throws -> Resource? {
        return try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            return try backgroundContext.performAndWaitThrowing {
                guard let managedObject = try managedObjectLocked(for: resource),
                      deliveryStateLocked(managedObject) == expectedState else { return nil }
                do {
                    // Materialize exact payload, metadata, and attachment generation
                    // while the same transaction that owns the state transition is held.
                    // Constructing first ensures a decoding failure cannot strand the row
                    // in an in-flight state.
                    let claimedResource = try Resource(
                        managedObject: managedObject,
                        metadataDirectoryUrl: metadataDirectoryUrl
                    )
                    setDeliveryStateLocked(inFlightState, on: managedObject)
                    setDeliveryOwnerLocked(deliveryOwnerToken, on: managedObject)
                    try contextSave(backgroundContext)
                    return claimedResource
                } catch {
                    backgroundContext.rollback()
                    throw error
                }
            }
        }
    }

    private func transition(_ resource: Resource,
                            from expectedStates: Set<PersistedReportState>?,
                            to targetState: PersistedReportState) throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            let didTransition = try backgroundContext.performAndWaitThrowing {
                guard let managedObject = try managedObjectLocked(for: resource) else {
                    throw RepositoryError.resourceNotFound
                }
                guard expectedStates?.contains(deliveryStateLocked(managedObject)) ?? true else {
                    return false
                }
                do {
                    setDeliveryStateLocked(targetState, on: managedObject)
                    setDeliveryOwnerLocked(nil, on: managedObject)
                    try contextSave(backgroundContext)
                    return true
                } catch {
                    backgroundContext.rollback()
                    throw error
                }
            }
            if didTransition, targetState != .terminalAwaitingDeletion {
                scheduleCapacityReconciliation()
            }
        }
    }

    /// Ordinary replay only sees reports whose initial attempt already failed transiently.
    /// Must be called while `transactionLock` is held.
    private func submissionEligibleResourcesLocked(
        _ resources: [Resource.ManagedObjectType]
    ) -> [Resource.ManagedObjectType] {
        return resources.filter { resource in
            deliveryStateLocked(resource) == .readyForRetry
        }
    }

    /// Materializes each eligible row independently so one damaged row cannot block every valid report behind it.
    /// Invalid rows are archived before their deletion is committed, then their owned files are cleaned after leaving the Core Data block.
    private func materializeEligiblePageLocked(
        _ objects: [Resource.ManagedObjectType],
        limit: Int
    ) throws -> MaterializedPage {
        guard limit > 0 else {
            return MaterializedPage(resources: [],
                                    cleanupIdentifiers: [],
                                    removedObjectCount: 0)
        }

        var resources = [Resource]()
        var invalidObjects = [Resource.ManagedObjectType]()

        for object in objects {
            do {
                resources.append(
                    try Resource(managedObject: object,
                                 metadataDirectoryUrl: metadataDirectoryUrl)
                )
            } catch {
                archiveInvalidPersistedObjectBestEffort(object, failure: error)
                invalidObjects.append(object)
            }

            if resources.count == limit {
                break
            }
        }

        let removedIdentifiers = _stageDeleteLocked(invalidObjects)
        if !invalidObjects.isEmpty {
            try _saveContextLocked()
        }

        // A corrupt hash is evidence, not ownership. Another committed row may use the same valid-looking UUID,
        // only remove UUID-scoped files when no survivor owns it.
        let survivingIdentifiers = Set(try _getResourcesLocked().compactMap {
            ($0.value(forKey: "hashProperty") as? String).flatMap(UUID.init(uuidString:))
        })
        let cleanupIdentifiers = removedIdentifiers.filter {
            !survivingIdentifiers.contains($0)
        }

        return MaterializedPage(resources: resources,
                                cleanupIdentifiers: cleanupIdentifiers,
                                removedObjectCount: invalidObjects.count)
    }

    private func reconcileOrphansAfterCorruptRows(_ page: MaterializedPage) {
        guard page.removedObjectCount > 0 else { return }
        // Every field on a corrupt row is untrusted, including a syntactically valid UUID and its attachment generation.
        // Reconcile against committed survivors after each quarantine so orphaned files are removed without touching survivor-owned files.
        reconcileStorageBestEffort(scheduleRetry: true)
    }

    // Keep raw database evidence local and bounded. Archival is best effort:
    // a full or unavailable diagnostics directory must not leave a protected corrupt row blocking delivery.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func archiveInvalidPersistedObjectBestEffort(
        _ object: Resource.ManagedObjectType,
        failure: Error
    ) {
        do {
            let rawIdentifier = object.value(forKey: "hashProperty") as? String
            let payload = object.value(forKey: "reportData") as? Data
            let stableSeed = [
                rawIdentifier ?? "missing-identifier",
                object.objectID.uriRepresentation().absoluteString
            ].joined(separator: "|")
            // Always include the Core Data object identity.
            // Two corrupt rows may carry the same valid-looking UUID and must retain separate diagnostic evidence.
            let archiveIdentifier = BacktraceReportIdentifier.digestIdentifier(
                for: Data(stableSeed.utf8)
            )
            let reportDirectoryUrl = persistedRowDeadLetterDirectoryUrl
                .appendingPathComponent(archiveIdentifier.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: reportDirectoryUrl,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.none])

            if let payload = payload {
                try payload.write(to: reportDirectoryUrl
                    .appendingPathComponent("payload.plcrash", isDirectory: false),
                                  options: .atomic)
            }

            var state: [String: Any] = [
                "failureType": String(describing: type(of: failure)),
                "failureDescription": String(describing: failure),
                "objectURI": object.objectID.uriRepresentation().absoluteString,
                "payloadLength": payload?.count ?? 0,
                "updatedAt": Date()
            ]
            if let rawIdentifier = rawIdentifier {
                state["hashProperty"] = rawIdentifier
            }
            if let dateAdded = object.value(forKey: "dateAdded") as? Date {
                state["dateAdded"] = dateAdded
            }
            if let deliveryOwner = object.value(forKey: "deliveryOwner") as? String {
                state["deliveryOwner"] = deliveryOwner
            }
            if let deliveryState = object.value(forKey: "deliveryStateRaw") as? NSNumber {
                state["deliveryStateRaw"] = deliveryState
            }
            if let retryCount = object.value(forKey: "retryCount") as? NSNumber {
                state["retryCount"] = retryCount
            } else if let retryCount = object.value(forKey: "retryCount") as? Int64 {
                state["retryCount"] = retryCount
            }
            if let attachmentMetadata = object.value(forKey: "attachmentPaths") {
                let safeAttachmentMetadata = propertyListSafeAttributes(
                    ["attachmentPaths": attachmentMetadata]
                )
                if let value = safeAttachmentMetadata.attributes["attachmentPaths"] {
                    state["attachmentPaths"] = value
                } else {
                    state["attachmentMetadataType"] = String(
                        describing: type(of: attachmentMetadata)
                    )
                }
            }

            let stateData = try PropertyListSerialization.data(fromPropertyList: state,
                                                               format: .binary,
                                                               options: 0)
            try stateData.write(to: reportDirectoryUrl
                .appendingPathComponent("state.plist", isDirectory: false),
                                options: .atomic)
            if let metadataIdentifier = rawIdentifier.flatMap(UUID.init(uuidString:)) {
                // The digest names this unique archive, while persisted sidecars remain keyed by the row's original UUID.
                archivePersistedMetadataBestEffort(identifier: metadataIdentifier,
                                                   reportDirectoryUrl: reportDirectoryUrl)
            }
            _ = trimPersistedRowDeadLettersBestEffort()
        } catch {
            BacktraceLogger.warning("Unable to preserve a corrupt persisted report before removing it.")
        }
    }

    private func archivePersistedMetadataBestEffort(identifier: UUID,
                                                    reportDirectoryUrl: URL) {
        do {
            let config = try AttributesStorage.AttributesConfig(fileName: identifier.uuidString,
                                                                directoryUrl: metadataDirectoryUrl)
            if FileManager.default.fileExists(atPath: config.fileUrl.path) {
                let data = try Data(contentsOf: config.fileUrl)
                try data.write(to: reportDirectoryUrl
                    .appendingPathComponent("attributes.plist", isDirectory: false),
                               options: .atomic)
            }
        } catch {
            BacktraceLogger.warning("Unable to preserve corrupt persisted report attributes.")
        }

        let pendingMetadataUrl = pendingMetadataDirectoryUrl
            .appendingPathComponent(identifier.uuidString, isDirectory: true)
        let archivedMetadataUrl = reportDirectoryUrl
            .appendingPathComponent("pending-metadata", isDirectory: true)
        guard FileManager.default.fileExists(atPath: pendingMetadataUrl.path),
              !FileManager.default.fileExists(atPath: archivedMetadataUrl.path) else { return }
        do {
            try FileManager.default.copyItem(at: pendingMetadataUrl, to: archivedMetadataUrl)
        } catch {
            BacktraceLogger.warning("Unable to preserve corrupt persisted pending metadata.")
        }
    }
    
    /// Convenience method for deleting the specified managed objects
    /// Must be called only within a `performAndWaitThrowing` block
    ///
    /// - Parameter managedObjects: Managed objects to delete
    /// - Throws: Any error from `save()`.
    private func _deleteLocked(_ managedObjects: [Resource.ManagedObjectType]) throws -> [UUID] {
        guard !managedObjects.isEmpty else { return [] }
        let identifiers = _stageDeleteLocked(managedObjects)
        try _saveContextLocked()
        return identifiers
    }

    private func _saveContextLocked() throws {
        do {
            try contextSave(backgroundContext)
        } catch {
            backgroundContext.rollback()
            throw error
        }
    }

    /// Stages deletion in the current Core Data transaction without committing it.
    private func _stageDeleteLocked(_ managedObjects: [Resource.ManagedObjectType]) -> [UUID] {
        let identifiers = managedObjects.compactMap {
            ($0.value(forKey: "hashProperty") as? String).flatMap(UUID.init(uuidString:))
        }
        managedObjects.forEach {
            backgroundContext.delete($0)
        }
        return identifiers
    }
    
    /// Counts the total number of resources in the store
    /// Must be called only within a `performAndWaitThrowing` block
    ///
    /// - Returns: Int
    /// - Throws: Any error from `count(for:)`
    private func _countResourcesLocked() throws -> Int {
        let resourcesCountRequest = NSFetchRequest<Resource.ManagedObjectType>(entityName: Resource.entityName)
        return try backgroundContext.count(for: resourcesCountRequest)
    }
    
    /// Selects capacity victims without disturbing a source handoff, a report awaiting its first attempt,
    /// or an active delivery claim. Terminal rows are cheapest to remove, followed by ordinary retry work.
    private func evictionCandidatesLocked(
        excluding identifiers: Set<UUID> = []
    ) throws -> [Resource.ManagedObjectType] {
        let ranked = try _getResourcesLocked().compactMap { managedObject -> EvictionCandidate? in
            guard let rank = deliveryStateLocked(managedObject).evictionRank,
                  let identifierValue = managedObject.value(forKey: "hashProperty") as? String,
                  let identifier = UUID(uuidString: identifierValue),
                  !identifiers.contains(identifier) else {
                return nil
            }
            return EvictionCandidate(
                object: managedObject,
                rank: rank,
                dateAdded: managedObject.value(forKey: "dateAdded") as? Date ?? .distantPast,
                identifier: identifier
            )
        }

        return ranked.sorted { left, right in
            if left.rank != right.rank {
                return left.rank < right.rank
            }
            if left.dateAdded != right.dateAdded {
                return left.dateAdded < right.dateAdded
            }
            return left.identifier.uuidString < right.identifier.uuidString
        }.map { $0.object }
    }

    /// Removes eligible records if the maximum number of records or total database size is exceeded.
    /// If every row is protected, the repository temporarily exceeds its configured limit,
    /// and a later reconciliation retries the same safe selection.
    /// Must be called only within a `performAndWaitThrowing` block
    /// - Throws: Any error from counting, removing records, or checking file size
    private func _removeOldestRecordIfNeededLocked(
        incomingRecordCount: Int = 1,
        excluding identifiers: Set<UUID> = []
    ) throws -> [UUID] {
        var removedIdentifiers = [UUID]()
        var candidates = try evictionCandidatesLocked(excluding: identifiers)

        func takeCandidates(_ requestedCount: Int) -> [Resource.ManagedObjectType] {
            let count = min(max(0, requestedCount), candidates.count)
            guard count > 0 else { return [] }
            let selected = Array(candidates.prefix(count))
            candidates.removeFirst(count)
            return selected
        }

        // check number of records
        if settings.maxRecordCount != BacktraceDatabaseSettings.unlimited {
            let removalCount = max(
                0,
                try _countResourcesLocked() + incomingRecordCount - settings.maxRecordCount
            )
            if removalCount > 0 {
                removedIdentifiers += _stageDeleteLocked(takeCandidates(removalCount))
            }
        }
        
        // SQLite's physical file size does not change until after the transaction commits (and
        // may retain free pages afterward). Stage at most one additional victim per save, then
        // re-evaluate the committed store on the next transaction instead of deleting every row
        // while polling an unchanged file size.
        if settings.maxDatabaseSize != BacktraceDatabaseSettings.unlimited {
            let size = try databaseSize(url)
            if size > settings.maxDatabaseSizeInBytes {
                BacktraceLogger.debug("Database exceeds its configured size before persistence: \(size)")
                removedIdentifiers += _stageDeleteLocked(takeCandidates(1))
            }
        }
        return removedIdentifiers
    }

    func reconcileStorage() throws {
        guard !isShutdown else { return }
        try withTransaction {
            guard !isShutdown else { return }
            let terminalIdentifiers = try backgroundContext.performAndWaitThrowing {
                let terminalResources = try _getResourcesLocked().filter { resource in
                    deliveryStateLocked(resource) == .terminalAwaitingDeletion
                }
                return try _deleteLocked(terminalResources)
            }
            cleanupResources(identifiers: terminalIdentifiers)

            let capacityIdentifiers = try backgroundContext.performAndWaitThrowing {
                do {
                    let identifiers = try _removeOldestRecordIfNeededLocked(incomingRecordCount: 0)
                    if !identifiers.isEmpty {
                        try _saveContextLocked()
                    }
                    return identifiers
                } catch {
                    backgroundContext.rollback()
                    throw error
                }
            }
            cleanupResources(identifiers: capacityIdentifiers)

            let storageSnapshot: (attachmentPaths: [String], identifiers: Set<UUID>) =
                try backgroundContext.performAndWaitThrowing {
                    let storedResources = try _getResourcesLocked()
                    let attachmentPaths = storedResources.flatMap {
                        ($0.value(forKey: "attachmentPaths") as? [String]) ?? []
                    }
                    let identifiers = Set(storedResources.compactMap {
                        ($0.value(forKey: "hashProperty") as? String).flatMap(UUID.init(uuidString:))
                    })
                    return (attachmentPaths, identifiers)
                }
            var cleanupWasDeferred = false
            do {
                try attachmentStore.reconcile(referencedAttachmentPaths: storageSnapshot.attachmentPaths)
            } catch RepositoryAttachmentStoreError.cleanupDeferred {
                cleanupWasDeferred = true
            }
            cleanupWasDeferred = !reconcileMetadataStorageBestEffort(
                reportIdentifiers: storageSnapshot.identifiers
            ) || cleanupWasDeferred
            cleanupWasDeferred = !reconcilePendingMetadataBestEffort(
                reportIdentifiers: storageSnapshot.identifiers
            ) || cleanupWasDeferred
            cleanupWasDeferred = !trimDeadLettersBestEffort() || cleanupWasDeferred
            cleanupWasDeferred = !trimPersistedRowDeadLettersBestEffort() || cleanupWasDeferred
            if cleanupWasDeferred {
                throw RepositoryAttachmentStoreError.cleanupDeferred
            }
        }
    }

    private func cleanupResources(identifiers: [UUID]) {
        let requestedIdentifiers = Set(identifiers)
        guard !requestedIdentifiers.isEmpty else { return }

        // UUID-scoped files can be shared by multiple rows if persistence is corrupted and two rows acquire the same valid-looking hash.
        // Every deletion path must fail closed while a committed survivor still owns that UUID;
        // later reconciliation removes only genuinely orphaned files.
        let storageSnapshot: (attachmentPaths: [String], identifiers: Set<UUID>)
        do {
            storageSnapshot = try backgroundContext.performAndWaitThrowing {
                let storedResources = try _getResourcesLocked()
                let attachmentPaths = storedResources.flatMap {
                    ($0.value(forKey: "attachmentPaths") as? [String]) ?? []
                }
                let identifiers = Set(storedResources.compactMap {
                    ($0.value(forKey: "hashProperty") as? String)
                        .flatMap(UUID.init(uuidString:))
                })
                return (attachmentPaths, identifiers)
            }
        } catch {
            BacktraceLogger.warning(
                "Deferred persisted report file cleanup because ownership could not be verified."
            )
            return
        }

        for identifier in requestedIdentifiers.subtracting(storageSnapshot.identifiers) {
            do {
                try AttributesStorage.remove(fileName: identifier.uuidString,
                                             directoryUrl: metadataDirectoryUrl)
                // Remove the pre-2.1.1 cache-backed sidecar after a repository row is deleted.
                try? AttributesStorage.remove(fileName: identifier.uuidString)
            } catch {
                BacktraceLogger.warning("Unable to remove persisted attributes for report \(identifier).")
            }
            try? FileManager.default.removeItem(at: pendingMetadataDirectoryUrl
                .appendingPathComponent(identifier.uuidString, isDirectory: true))
        }

        // Attachment paths are durable references and must be treated independently from the row UUID.
        // A damaged row can make a surviving row reference a generation stored below another identifier's directory.
        // Reconcile from the committed reference set instead of deleting that directory eagerly.
        do {
            try attachmentStore.reconcile(
                referencedAttachmentPaths: storageSnapshot.attachmentPaths
            )
        } catch {
            BacktraceLogger.warning("Deferred persisted attachment cleanup after row deletion.")
        }
    }

    private func reconcileAttachmentsFromCommittedRowsBestEffort() {
        do {
            let attachmentPaths = try backgroundContext.performAndWaitThrowing {
                try _getResourcesLocked().flatMap {
                    ($0.value(forKey: "attachmentPaths") as? [String]) ?? []
                }
            }
            try attachmentStore.reconcile(referencedAttachmentPaths: attachmentPaths)
        } catch {
            BacktraceLogger.warning(
                "Deferred cleanup of superseded persisted attachment generations."
            )
        }
    }

    private func reconcileMetadataStorageBestEffort(reportIdentifiers: Set<UUID>) -> Bool {
        var cleanupSucceeded = true
        for identifier in reportIdentifiers {
            do {
                let repositoryConfig = try AttributesStorage.AttributesConfig(
                    fileName: identifier.uuidString,
                    directoryUrl: metadataDirectoryUrl
                )
                guard !FileManager.default.fileExists(atPath: repositoryConfig.fileUrl.path),
                      let legacyAttributes = try? AttributesStorage.retrieve(fileName: identifier.uuidString) else {
                    continue
                }
                try AttributesStorage.store(legacyAttributes,
                                            fileName: identifier.uuidString,
                                            directoryUrl: metadataDirectoryUrl)
                try? AttributesStorage.remove(fileName: identifier.uuidString)
            } catch {
                cleanupSucceeded = false
                BacktraceLogger.warning("Deferred retry metadata migration after cleanup failed.")
            }
        }

        guard let files = try? FileManager.default.contentsOfDirectory(at: metadataDirectoryUrl,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else {
            BacktraceLogger.warning("Deferred orphan metadata cleanup because the directory could not be enumerated.")
            return false
        }
        for fileUrl in files where fileUrl.pathExtension == "plist" {
            guard let identifier = UUID(uuidString: fileUrl.deletingPathExtension().lastPathComponent),
                  !reportIdentifiers.contains(identifier) else { continue }
            do {
                try FileManager.default.removeItem(at: fileUrl)
            } catch {
                cleanupSucceeded = false
                BacktraceLogger.warning("Deferred removal of an orphan retry metadata file.")
            }
        }
        return cleanupSucceeded
    }

    private func preservePendingMetadataFilesLocked(_ resource: Resource) {
        guard !resource.pendingMetadataFilePaths.isEmpty else { return }
        let reportDirectoryUrl = pendingMetadataDirectoryUrl
            .appendingPathComponent(resource.identifier.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: reportDirectoryUrl,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.none])
            for (index, path) in resource.pendingMetadataFilePaths.enumerated() {
                let sourceUrl = URL(fileURLWithPath: path).standardizedFileURL
                guard FileManager.default.fileExists(atPath: sourceUrl.path) else { continue }
                let data = try Data(contentsOf: sourceUrl)
                let destinationUrl = reportDirectoryUrl.appendingPathComponent(
                    "\(index)-\(sourceUrl.lastPathComponent)",
                    isDirectory: false
                )
                try data.write(to: destinationUrl, options: .atomic)
            }
        } catch {
            resource.attributes[BacktracePendingCrashMetadata.sidecarPreservationErrorKey] = true
            BacktraceLogger.warning("Unable to preserve a raw pending-crash metadata sidecar.")
        }
    }

    /// Archives an invalid PLCrashReporter source before it is purged from the live namespace.
    /// The archive is bounded, while the attempt count preserves evidence of recurring purge failures.
    func deadLetterPendingCrash(data: Data,
                                rawSidecarPaths: [String],
                                diagnostics: Attributes,
                                failure: Error) throws {
        try withTransaction {
            let identifier = BacktraceReportIdentifier.pendingReportIdentifier(for: data)
            let reportDirectoryUrl = deadLetterDirectoryUrl
                .appendingPathComponent(identifier.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: reportDirectoryUrl,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.none])

            let payloadUrl = reportDirectoryUrl.appendingPathComponent("payload.plcrash", isDirectory: false)
            if !FileManager.default.fileExists(atPath: payloadUrl.path) {
                try data.write(to: payloadUrl, options: .atomic)
            }

            let sidecarDirectoryUrl = reportDirectoryUrl.appendingPathComponent("sidecars", isDirectory: true)
            var missingSidecarCount = 0
            var sidecarCopyFailureCount = 0
            for (index, path) in rawSidecarPaths.enumerated() {
                let sourceUrl = URL(fileURLWithPath: path).standardizedFileURL
                guard FileManager.default.fileExists(atPath: sourceUrl.path) else {
                    missingSidecarCount += 1
                    continue
                }
                do {
                    try FileManager.default.createDirectory(at: sidecarDirectoryUrl,
                                                            withIntermediateDirectories: true,
                                                            attributes: [.protectionKey: FileProtectionType.none])
                    let destinationUrl = sidecarDirectoryUrl
                        .appendingPathComponent("\(index)-\(sourceUrl.lastPathComponent)", isDirectory: false)
                    try Data(contentsOf: sourceUrl).write(to: destinationUrl, options: .atomic)
                } catch {
                    sidecarCopyFailureCount += 1
                    BacktraceLogger.warning("Unable to preserve an optional dead-letter sidecar.")
                }
            }

            let stateUrl = reportDirectoryUrl.appendingPathComponent("state.plist", isDirectory: false)
            var attemptCount = 0
            if let stateData = try? Data(contentsOf: stateUrl),
               let state = try? PropertyListSerialization.propertyList(from: stateData,
                                                                         options: [],
                                                                         format: nil) as? [String: Any] {
                attemptCount = state["attemptCount"] as? Int ?? 0
            }
            attemptCount += 1
            var state: [String: Any] = [
                "attemptCount": attemptCount,
                "failureType": String(describing: type(of: failure)),
                "updatedAt": Date()
            ]
            var stateDiagnostics = propertyListSafeAttributes(diagnostics).attributes
            stateDiagnostics[BacktracePendingCrashMetadata.deadLetterMissingSidecarsKey] = missingSidecarCount
            stateDiagnostics[BacktracePendingCrashMetadata.deadLetterSidecarCopyFailuresKey] =
                sidecarCopyFailureCount
            state["diagnostics"] = stateDiagnostics
            let stateData = try PropertyListSerialization.data(fromPropertyList: state,
                                                               format: .binary,
                                                               options: 0)
            try stateData.write(to: stateUrl, options: .atomic)
            _ = trimDeadLettersBestEffort()
        }
    }

    private func reconcilePendingMetadataBestEffort(reportIdentifiers: Set<UUID>) -> Bool {
        guard FileManager.default.fileExists(atPath: pendingMetadataDirectoryUrl.path) else { return true }
        guard let reportDirectories = try? FileManager.default.contentsOfDirectory(
            at: pendingMetadataDirectoryUrl,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            BacktraceLogger.warning("Deferred pending metadata cleanup because its directory could not be enumerated.")
            return false
        }
        var cleanupSucceeded = true
        for reportDirectoryUrl in reportDirectories {
            guard let identifier = UUID(uuidString: reportDirectoryUrl.lastPathComponent),
                  !reportIdentifiers.contains(identifier) else { continue }
            do {
                try FileManager.default.removeItem(at: reportDirectoryUrl)
            } catch {
                cleanupSucceeded = false
                BacktraceLogger.warning("Deferred removal of orphan pending metadata.")
            }
        }
        return cleanupSucceeded
    }

    private func trimDeadLettersBestEffort() -> Bool {
        guard FileManager.default.fileExists(atPath: deadLetterDirectoryUrl.path) else { return true }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: deadLetterDirectoryUrl,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            BacktraceLogger.warning("Deferred dead-letter cleanup because its directory could not be enumerated.")
            return false
        }
        guard entries.count > maximumPendingCrashDeadLetters else { return true }
        var cleanupSucceeded = true
        let sortedEntries = entries.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        for entry in sortedEntries.prefix(entries.count - maximumPendingCrashDeadLetters) {
            do {
                try FileManager.default.removeItem(at: entry)
            } catch {
                cleanupSucceeded = false
                BacktraceLogger.warning("Deferred removal of an expired pending-crash dead letter.")
            }
        }
        return cleanupSucceeded
    }

    private func trimPersistedRowDeadLettersBestEffort() -> Bool {
        guard FileManager.default.fileExists(atPath: persistedRowDeadLetterDirectoryUrl.path) else {
            return true
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: persistedRowDeadLetterDirectoryUrl,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            BacktraceLogger.warning("Deferred corrupt persisted-report archive cleanup.")
            return false
        }
        guard entries.count > maximumPendingCrashDeadLetters else { return true }

        var cleanupSucceeded = true
        let sortedEntries = entries.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return left < right
        }
        for entry in sortedEntries.prefix(entries.count - maximumPendingCrashDeadLetters) {
            do {
                try FileManager.default.removeItem(at: entry)
            } catch {
                cleanupSucceeded = false
                BacktraceLogger.warning("Deferred removal of an expired corrupt persisted-report archive.")
            }
        }
        return cleanupSucceeded
    }

    private func reconcileStorageBestEffort(scheduleRetry: Bool) {
        guard !isShutdown else { return }
        do {
            try reconcileStorage()
        } catch {
            BacktraceLogger.warning("Repository orphan reconciliation was deferred.")
            guard scheduleRetry, !isShutdown else { return }
            maintenanceQueue.asyncAfter(deadline: .now() + maintenanceRetryDelay) { [weak self] in
                self?.reconcileStorageBestEffort(scheduleRetry: false)
            }
        }
    }

    /// Capacity may be exceeded while every row is protected by a source handoff,
    /// a first-delivery opportunity, or an active claim.
    /// Recheck after a protected row becomes safely evictable without extending response finalization.
    private func scheduleCapacityReconciliation() {
        guard settings.maxRecordCount != BacktraceDatabaseSettings.unlimited ||
                settings.maxDatabaseSize != BacktraceDatabaseSettings.unlimited,
              !isShutdown else { return }

        maintenanceStateLock.lock()
        capacityReconciliationRequested = true
        guard !capacityReconciliationScheduled else {
            maintenanceStateLock.unlock()
            return
        }
        capacityReconciliationScheduled = true
        maintenanceStateLock.unlock()

        maintenanceQueue.asyncAfter(deadline: .now() + maintenanceRetryDelay) { [weak self] in
            self?.runScheduledCapacityReconciliation()
        }
    }

    /// Runs one coalesced capacity pass.
    /// A transition that becomes evictable while the pass is running sets `capacityReconciliationRequested` again,
    /// the single-flight worker performs another pass instead of dropping the wakeup between reconciliation and flag cleanup.
    private func runScheduledCapacityReconciliation() {
        maintenanceStateLock.lock()
        capacityReconciliationRequested = false
        maintenanceStateLock.unlock()

        if !isShutdown {
            reconcileStorageBestEffort(scheduleRetry: false)
            if !isShutdown {
                capacityReconciliationDidRun?(self)
            }
        }

        maintenanceStateLock.lock()
        let shouldRunAgain = capacityReconciliationRequested && !isShutdown
        if !shouldRunAgain {
            capacityReconciliationScheduled = false
        }
        maintenanceStateLock.unlock()

        if shouldRunAgain {
            maintenanceQueue.asyncAfter(deadline: .now() + maintenanceRetryDelay) { [weak self] in
                self?.runScheduledCapacityReconciliation()
            }
        }
    }

    internal var isShutdown: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }

    /// Latches retained repository maintenance off before transport cancellation can unblock a producer.
    /// Normal Cocoa clients never invoke this native-only hook.
    internal func prepareForNativeBridgeShutdown() {
        lifecycleLock.lock()
        shutdownRequested = true
        lifecycleLock.unlock()
    }

    /// Waits for currently admitted local Core Data/file transactions after transport cancellation,
    /// then synchronously detaches this repository's persistent stores.
    /// The Unity bridge retains its first reporter for process lifetime,
    /// relying on object deallocation alone would keep SQLite descriptors open after `Disable()`.
    /// No fixed completion deadline is promised.
    internal func finishNativeBridgeShutdown() {
        lifecycleLock.lock()
        let sharedStateHandle = repositorySharedStateHandle
        lifecycleLock.unlock()
        guard let sharedStateHandle = sharedStateHandle else { return }
        let sharedState = sharedStateHandle.state

        sharedState.transactionLock.lock()
        defer { sharedState.transactionLock.unlock() }

        // A concurrent shutdown may have completed while this call waited.
        lifecycleLock.lock()
        let stillOwnsSharedState = repositorySharedStateHandle === sharedStateHandle
        lifecycleLock.unlock()
        guard stillOwnsSharedState else { return }

        do {
            try sharedState.advisoryLock.withExclusiveLock {
                try backgroundContext.performAndWaitThrowing {
                    backgroundContext.reset()
                    guard let coordinator = backgroundContext.persistentStoreCoordinator else {
                        return
                    }
                    for store in coordinator.persistentStores {
                        try coordinator.remove(store)
                    }
                }
            }
        } catch {
            // Shutdown is best effort and idempotent.
            // Keep diagnostics generic because persistent-store errors may contain application filesystem paths.
            BacktraceLogger.warning("Unable to close retry repository storage during shutdown.")
        }

        // The crash reporter remains installed, but the disabled client cannot perform more repository work.
        // Release this repository's state even if Core Data teardown was best effort;
        // another live repository retains a shared state independently.
        sharedStateHandle.release()
        lifecycleLock.lock()
        if repositorySharedStateHandle === sharedStateHandle {
            repositorySharedStateHandle = nil
        }
        lifecycleLock.unlock()
    }

    internal func shutdownForNativeBridge() {
        prepareForNativeBridgeShutdown()
        finishNativeBridgeShutdown()
    }

    private func restoreAttributes(_ data: Data?, config: AttributesStorage.AttributesConfig) {
        do {
            if let data = data {
                try data.write(to: config.fileUrl, options: .atomic)
            } else {
                try AttributesStorage.remove(fileName: config.fileUrl.deletingPathExtension().lastPathComponent,
                                             directoryUrl: metadataDirectoryUrl)
            }
        } catch {
            BacktraceLogger.error("Unable to roll back persisted report attributes.")
        }
    }

    private func propertyListSafeAttributes(_ attributes: Attributes) -> (
        attributes: Attributes,
        removedValueCount: Int
    ) {
        var safeAttributes = Attributes()
        for (key, value) in attributes where
            PropertyListSerialization.propertyList([key: value], isValidFor: .binary) {
            safeAttributes[key] = value
        }
        return (safeAttributes, attributes.count - safeAttributes.count)
    }

    private func withTransaction<T>(_ body: () throws -> T) throws -> T {
        return try withSharedStateTransaction { _ in
            try body()
        }
    }

    private func withSharedStateTransaction<T>(
        _ body: (RepositorySharedState) throws -> T
    ) throws -> T {
        lifecycleLock.lock()
        let sharedStateHandle = shutdownRequested ? nil : repositorySharedStateHandle
        lifecycleLock.unlock()
        guard let sharedStateHandle = sharedStateHandle else {
            throw RepositoryError.repositoryShutdown
        }
        let sharedState = sharedStateHandle.state

        sharedState.transactionLock.lock()
        defer { sharedState.transactionLock.unlock() }

        // Shutdown can win while this operation waits behind an admitted transaction.
        // Recheck after acquiring the transaction lock,
        // without ever holding lifecycleLock while waiting for another lock.
        lifecycleLock.lock()
        let isActive = !shutdownRequested &&
            repositorySharedStateHandle === sharedStateHandle
        lifecycleLock.unlock()
        guard isActive else {
            throw RepositoryError.repositoryShutdown
        }

        return try sharedState.advisoryLock.withExclusiveLock {
            backgroundContext.performAndWait {
                if !backgroundContext.hasChanges {
                    // Separate repository instances and processes use separate containers.
                    // Reset at the database lock boundary before observing or mutating row delivery state.
                    backgroundContext.reset()
                }
            }
            return try body(sharedState)
        }
    }
}
