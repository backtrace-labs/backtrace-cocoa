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
    private let descriptor: Int32
    private let localLock = NSRecursiveLock()
    private var lockDepth = 0

    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else {
            throw RepositoryFileLockError.openFailed(errno)
        }
    }

    deinit {
        Darwin.close(descriptor)
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
        while setRepositoryFileLock(descriptor, command: command, type: Int16(F_WRLCK)) != 0 {
            guard errno == EINTR else {
                throw RepositoryFileLockError.lockFailed(errno)
            }
        }
    }
}

/// A process-lifetime lease used to distinguish abandoned in-flight rows from reports actively owned by another process sharing the same SQLite store.
private final class RepositoryProcessLease {
    let token: String
    private let directoryUrl: URL
    private let descriptor: Int32

    init(databaseUrl: URL, token: String) throws {
        self.token = token
        directoryUrl = databaseUrl.deletingLastPathComponent()
            .appendingPathComponent("BacktraceReportLocks", isDirectory: true)
            .appendingPathComponent("Leases", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryUrl,
                                                withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.none])
        let leaseUrl = Self.leaseUrl(directoryUrl: directoryUrl, owner: token)
        descriptor = Darwin.open(leaseUrl.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else {
            throw RepositoryFileLockError.openFailed(errno)
        }
        guard setRepositoryFileLock(descriptor, command: F_SETLK, type: Int16(F_WRLCK)) == 0 else {
            let lockError = errno
            Darwin.close(descriptor)
            throw RepositoryFileLockError.lockFailed(lockError)
        }
        removeStaleLeaseFiles()
    }

    deinit {
        _ = setRepositoryFileLock(descriptor, command: F_SETLK, type: Int16(F_UNLCK))
        Darwin.close(descriptor)
    }

    func isOwnerAlive(_ owner: String) -> Bool {
        guard owner != token else { return true }
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

private final class RepositoryTransactionLockRegistry {
    static let shared = RepositoryTransactionLockRegistry()
    private static let processSessionToken = UUID().uuidString

    private let registryLock = NSLock()
    private var locks = [String: NSRecursiveLock]()
    private var advisoryLocks = [String: RepositoryAdvisoryFileLock]()
    private var processLeases = [String: RepositoryProcessLease]()
    private var completedStaleRecoveryKeys = Set<String>()

    private func key(for databaseUrl: URL) -> String {
        return databaseUrl.standardizedFileURL.path
    }

    func transactionLock(for databaseUrl: URL) -> NSRecursiveLock {
        let key = key(for: databaseUrl)
        registryLock.lock()
        defer { registryLock.unlock() }
        if let lock = locks[key] {
            return lock
        }
        let lock = NSRecursiveLock()
        locks[key] = lock
        return lock
    }

    func advisoryLock(for databaseUrl: URL) throws -> RepositoryAdvisoryFileLock {
        let key = key(for: databaseUrl)
        registryLock.lock()
        defer { registryLock.unlock() }
        if let lock = advisoryLocks[key] {
            return lock
        }
        let lock = try RepositoryAdvisoryFileLock(
            url: databaseUrl.appendingPathExtension("backtrace.lock")
        )
        advisoryLocks[key] = lock
        return lock
    }

    func hasCompletedStaleRecovery(for databaseUrl: URL) -> Bool {
        registryLock.lock()
        defer { registryLock.unlock() }
        return completedStaleRecoveryKeys.contains(key(for: databaseUrl))
    }

    func markStaleRecoveryCompleted(for databaseUrl: URL) {
        registryLock.lock()
        completedStaleRecoveryKeys.insert(key(for: databaseUrl))
        registryLock.unlock()
    }

    func processLease(for databaseUrl: URL) throws -> RepositoryProcessLease {
        let key = key(for: databaseUrl)
        registryLock.lock()
        defer { registryLock.unlock() }
        if let lease = processLeases[key] {
            return lease
        }
        let lease = try RepositoryProcessLease(databaseUrl: databaseUrl,
                                               token: Self.processSessionToken)
        processLeases[key] = lease
        return lease
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

    let backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings
    let url: URL
    let attachmentStore: RepositoryAttachmentStore
    let metadataDirectoryUrl: URL
    private let transactionLock: NSRecursiveLock
    private let databaseAdvisoryLock: RepositoryAdvisoryFileLock
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
        self.transactionLock = RepositoryTransactionLockRegistry.shared.transactionLock(for: resolvedDatabaseUrl)
        let sharedAdvisoryLock: RepositoryAdvisoryFileLock
        do {
            sharedAdvisoryLock = try RepositoryTransactionLockRegistry.shared.advisoryLock(
                for: resolvedDatabaseUrl
            )
            self.databaseAdvisoryLock = sharedAdvisoryLock
            // Lease creation and stale-file cleanup must share the database lock with liveness
            // checks. Otherwise another process can unlink a newly opened lease before its owner
            // acquires the lease lock, making a live claim appear abandoned.
            let processLease = try sharedAdvisoryLock.withExclusiveLock {
                try RepositoryTransactionLockRegistry.shared.processLease(for: resolvedDatabaseUrl)
            }
            self.deliveryOwnerToken = deliveryOwnerToken ?? processLease.token
            self.deliveryOwnerIsAlive = deliveryOwnerIsAlive ?? { processLease.isOwnerAlive($0) }
        } catch {
            throw RepositoryError.persistentRepositoryInitError(
                details: "The retry database process lock could not be prepared."
            )
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
        return try withTransaction {
            // A process that owned a claim may exit after this client starts.
            // Recheck leases at every submission fetch so the surviving client can eventually resume that row.
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            return try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
                let initial = try _getResourcesLocked(sortDescriptors: sortDescriptors).filter {
                    deliveryStateLocked($0) == .readyForInitialSubmission
                }
                return try initial.prefix(count).map {
                    try Resource(managedObject: $0, metadataDirectoryUrl: metadataDirectoryUrl)
                }
            }
        }
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

    /// Recovers claims abandoned by a previous process exactly once for this database in the current process.
    /// A second live client must not rewind a claim owned by the first client.
    func recoverStaleInFlightReportsOncePerProcess() throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            let registry = RepositoryTransactionLockRegistry.shared
            guard !registry.hasCompletedStaleRecovery(for: url) else { return }
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            // Mark only after the Core Data transaction commits.
            // A failed first client therefore leaves recovery available to a later client in the same process.
            registry.markStaleRecoveryCompleted(for: url)
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
                let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
                let fetchRequestResults = try _getResourcesLocked(predicate: predicate, fetchLimit: 100)
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
        return try withTransaction {
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            return try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
                let latest = submissionEligibleResourcesLocked(
                    try _getResourcesLocked(sortDescriptors: sortDescriptors)
                )
                return try latest.prefix(count).map {
                    try Resource(managedObject: $0, metadataDirectoryUrl: metadataDirectoryUrl)
                }
            }
        }
    }
    
    /// Fetches the oldest (by `dateAdded`) resources
    /// - Parameter count: Int : Default`1`
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getOldest(count: Int = 1) throws -> [Resource] {
        return try withTransaction {
            try resetInFlightReportsLocked(onlyAbandonedOwners: true)
            return try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
                let oldest = submissionEligibleResourcesLocked(
                    try _getResourcesLocked(sortDescriptors: sortDescriptors)
                )
                return try oldest.prefix(count).map {
                    try Resource(managedObject: $0, metadataDirectoryUrl: metadataDirectoryUrl)
                }
            }
        }
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
            if cleanupWasDeferred {
                throw RepositoryAttachmentStoreError.cleanupDeferred
            }
        }
    }

    private func cleanupResources(identifiers: [UUID]) {
        for identifier in Set(identifiers) {
            do {
                try AttributesStorage.remove(fileName: identifier.uuidString,
                                             directoryUrl: metadataDirectoryUrl)
                // Remove the pre-2.1.1 cache-backed sidecar after a repository row is deleted.
                try? AttributesStorage.remove(fileName: identifier.uuidString)
            } catch {
                BacktraceLogger.warning("Unable to remove persisted attributes for report \(identifier).")
            }
            do {
                try attachmentStore.removeAttachments(for: identifier)
            } catch {
                BacktraceLogger.warning("Unable to remove persisted attachments for report \(identifier).")
            }
            try? FileManager.default.removeItem(at: pendingMetadataDirectoryUrl
                .appendingPathComponent(identifier.uuidString, isDirectory: true))
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

    /// Waits for currently admitted local Core Data/file transactions after transport
    /// cancellation. No fixed completion deadline is promised.
    internal func finishNativeBridgeShutdown() {
        transactionLock.lock()
        transactionLock.unlock()
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return try databaseAdvisoryLock.withExclusiveLock {
            backgroundContext.performAndWait {
                if !backgroundContext.hasChanges {
                    // Separate repository instances and processes use separate containers.
                    // Reset at the database lock boundary before observing or mutating row delivery state.
                    backgroundContext.reset()
                }
            }
            return try body()
        }
    }
}
