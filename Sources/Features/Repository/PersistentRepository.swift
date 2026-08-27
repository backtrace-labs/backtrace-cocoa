import Foundation
import CoreData

private final class BacktraceResourceBundleToken: NSObject {}

private let maximumCorruptReportStateArchives = 3
private let maximumPendingCrashDeadLetters = 10

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

enum PersistedReportState: String {
    case awaitingSourcePurge
    case readyForSubmission
    case terminalAwaitingDeletion
}

/// Persists `PersistentStorable` objects using Core Data
/// Manages concurrency by using a private-queue context and `performAndWaitThrowing` for all operations
final class PersistentRepository<Resource: PersistentStorable> {

    let backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings
    let url: URL
    let attachmentStore: RepositoryAttachmentStore
    let metadataDirectoryUrl: URL
    private let transactionLock = NSRecursiveLock()
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false
    private let maintenanceQueue = DispatchQueue(label: "backtrace.repository.maintenance", qos: .utility)
    private let maintenanceRetryDelay: DispatchTimeInterval
    private let contextSave: (NSManagedObjectContext) throws -> Void
    private let databaseSize: (URL) throws -> Int

    private var stateFileUrl: URL {
        return metadataDirectoryUrl.appendingPathComponent("report-states.plist", isDirectory: false)
    }

    private var pendingMetadataDirectoryUrl: URL {
        return metadataDirectoryUrl.appendingPathComponent("PendingMetadata", isDirectory: true)
    }

    private var deadLetterDirectoryUrl: URL {
        return metadataDirectoryUrl.appendingPathComponent("DeadLetters", isDirectory: true)
    }

    /// Creates a new `PersistentRepository`
    /// - Parameter settings: BacktraceDatabaseSettings
    /// - Throws: `RepositoryError`
    init(settings: BacktraceDatabaseSettings,
         startupReconciliation: ((PersistentRepository<Resource>) throws -> Void)? = nil,
         attachmentCopy: ((URL, URL) throws -> Void)? = nil,
         attachmentResourceValues: ((URL) throws -> URLResourceValues)? = nil,
         databaseSize: @escaping (URL) throws -> Int = { try BacktraceFileManager.sizeOfFile(at: $0) },
         contextSave: @escaping (NSManagedObjectContext) throws -> Void = { try $0.save() },
         maintenanceRetryDelay: DispatchTimeInterval = .seconds(1)) throws {
        self.settings = settings
        self.databaseSize = databaseSize
        self.contextSave = contextSave
        self.maintenanceRetryDelay = maintenanceRetryDelay
        let momdName = "Model"
        guard let modelURL = Self.resolveModelUrl(modelName: momdName) else {
            throw RepositoryError
                .persistentRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
        }
        BacktraceLogger.debug("Resolved Core Data model at: \(modelURL.path)")
        guard let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            throw RepositoryError.persistentRepositoryInitError(
                details: "The packaged retry database model could not be loaded."
            )
        }
        if #available(iOS 10.0, tvOS 10.0, macOS 10.12, *) {
            let persistentContainer = NSPersistentContainer(name: momdName, managedObjectModel: managedObjectModel)
            do {
                try PersistentRepository.migration(coordinator: persistentContainer.persistentStoreCoordinator,
                                                   storeDir: NSPersistentContainer.defaultDirectoryURL(),
                                                   managedObject: managedObjectModel)
            } catch {
                throw RepositoryError.persistentRepositoryInitError(
                    details: "The retry database could not be prepared for loading."
                )
            }
            let dispatch = DispatchSemaphore(value: 0)
            var loadPersistentStoresError: Error?
            var url: URL?
            persistentContainer.loadPersistentStores { (storeDescription, error) in
                BacktraceLogger.debug("Loaded persistent stores, store description: \(storeDescription)")
                loadPersistentStoresError = error
                url = storeDescription.url
                dispatch.signal()
            }
            dispatch.wait()
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
            guard let storeDir =
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).last else {
                throw RepositoryError.persistentRepositoryInitError(details: "Unable to resolve document directory") }
            let storeURL = storeDir.appendingPathComponent("Model.sqlite")
            do {
                try PersistentRepository.migration(coordinator: psc,
                                                   storeDir: storeDir,
                                                   managedObject: managedObjectModel)
                try psc.addPersistentStore(ofType: NSSQLiteStoreType,
                                           configurationName: nil,
                                           at: storeURL,
                                           options: nil)
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
        performStartupReconciliation(startupReconciliation)
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
        return moduleUrl
#else
        let frameworkBundle = Bundle(for: BacktraceResourceBundleToken.self)
        var bundles = [frameworkBundle]
        if frameworkBundle.bundleURL != Bundle.main.bundleURL {
            bundles.append(Bundle.main)
        }

        for bundle in bundles {
            let directUrl = bundle.url(forResource: modelName, withExtension: "momd")
            BacktraceLogger.debug("Core Data model candidate (direct, \(bundle.bundleURL.path)): \(directUrl?.path ?? "missing")")
            if let directUrl = directUrl { return directUrl }
        }

        for bundle in bundles {
            let nestedBundleUrl = bundle.url(forResource: "BacktraceResources", withExtension: "bundle")
            let nestedUrl = nestedBundleUrl
                .flatMap { Bundle(url: $0) }?
                .url(forResource: modelName, withExtension: "momd")
            BacktraceLogger.debug("Core Data model candidate (nested, \(bundle.bundleURL.path)): \(nestedUrl?.path ?? "missing")")
            if let nestedUrl = nestedUrl { return nestedUrl }
        }

        BacktraceLogger.error("Unable to resolve \(modelName).momd from direct or BacktraceResources.bundle locations")
        return nil
#endif
    }

    
    /// Attempts to migrate the persistent store if the existing store is incompatible with the current `NSManagedObjectModel`
    /// - Parameters:
    ///   - coordinator: NSPersistentStoreCoordinator
    ///   - storeDir: URL
    ///   - managedObject: NSManagedObjectModel
    static func migration(coordinator: NSPersistentStoreCoordinator,
                          storeDir: URL,
                          managedObject: NSManagedObjectModel) throws {
        let storeUrl = storeDir.appendingPathComponent("Model.sqlite")

        guard FileManager.default.fileExists(atPath: storeUrl.path),
            let metadata = try? NSPersistentStoreCoordinator
            .metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeUrl, options: nil),
            !managedObject.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return }
        if #available(macOS 10.11, *) {
            try coordinator.destroyPersistentStore(at: storeUrl, ofType: NSSQLiteStoreType, options: nil)
        } else {
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
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
            try _save(resource, isPendingCrash: false)
        }
    }

    /// Durably saves a pending crash before its PLCrashReporter source may be purged.
    ///
    /// The report is initially ineligible for submission. It becomes eligible only after PLCrashReporter confirms
    /// that its source has been purged, preventing replay from submitting the same source more than once.
    func savePending(_ resource: Resource) throws {
        try withTransaction {
            var states = try loadReportStatesLocked()
            let previousState = states[resource.identifier.uuidString]
            states[resource.identifier.uuidString] = PersistedReportState.awaitingSourcePurge.rawValue
            try storeReportStatesLocked(states)

            do {
                preservePendingMetadataFilesLocked(resource)
                try _save(resource, isPendingCrash: true)
            } catch {
                states[resource.identifier.uuidString] = previousState
                do {
                    try storeReportStatesLocked(states)
                } catch {
                    BacktraceLogger.error("Unable to restore pending report eligibility after persistence failed.")
                }
                throw error
            }
        }
    }

    private func _save(_ resource: Resource, isPendingCrash: Bool) throws {
        let existingAttachmentPaths = try backgroundContext.performAndWaitThrowing {
            let predicate = NSPredicate(format: "hashProperty == %@", resource.identifier.uuidString)
            return try _getResourcesLocked(predicate: predicate, fetchLimit: 1).first?
                .value(forKey: "attachmentPaths") as? [String] ?? []
        }
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
    }

    /// Promotes a durably persisted pending report only after its PLCrashReporter source is gone.
    func markReadyForSubmission(_ resource: Resource) throws {
        try withTransaction {
            var states = try loadReportStatesLocked()
            states[resource.identifier.uuidString] = PersistedReportState.readyForSubmission.rawValue
            try storeReportStatesLocked(states)
        }
    }

    /// A process may terminate after source purge but before the eligibility transition is written.
    /// When there is no matching pending PLCrashReporter source, those rows are safe to replay.
    func markAwaitingReportsReady(except identifier: UUID? = nil) throws {
        try withTransaction {
            let preservedIdentifier = identifier?.uuidString
            var states: [String: String]
            do {
                states = try loadReportStatesLocked()
            } catch {
                quarantineCorruptReportStatesLocked()
                if let preservedIdentifier = preservedIdentifier {
                    states = [preservedIdentifier: PersistedReportState.awaitingSourcePurge.rawValue]
                } else {
                    states = [:]
                }
            }
            let identifiersToPromote = states.compactMap { key, value in
                value == PersistedReportState.awaitingSourcePurge.rawValue && key != preservedIdentifier ? key : nil
            }
            for key in identifiersToPromote {
                states[key] = PersistedReportState.readyForSubmission.rawValue
            }
            try storeReportStatesLocked(states)
        }
    }

    func persistedState(for resource: Resource) throws -> PersistedReportState {
        return try withTransaction {
            let value = try loadReportStatesLocked()[resource.identifier.uuidString]
            return PersistedReportState(rawValue: value ?? "") ?? .readyForSubmission
        }
    }

    /// Durably excludes a terminally handled row from replay before attempting its cleanup.
    func markTerminalForDeletion(_ resource: Resource) throws {
        try withTransaction {
            guard !isShutdown else { throw RepositoryError.repositoryShutdown }
            var states = try loadReportStatesLocked()
            states[resource.identifier.uuidString] = PersistedReportState.terminalAwaitingDeletion.rawValue
            try storeReportStatesLocked(states)
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
            try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
                let latest = try submissionEligibleResourcesLocked(
                    _getResourcesLocked(sortDescriptors: sortDescriptors)
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
            try backgroundContext.performAndWaitThrowing {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
                let oldest = try submissionEligibleResourcesLocked(
                    _getResourcesLocked(sortDescriptors: sortDescriptors)
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

    /// Excludes rows whose PLCrashReporter source has not been confirmed purged.
    /// Must be called while `transactionLock` is held.
    private func submissionEligibleResourcesLocked(
        _ resources: [Resource.ManagedObjectType]
    ) throws -> [Resource.ManagedObjectType] {
        let states = try loadReportStatesLocked()
        return resources.filter { resource in
            guard let identifier = resource.value(forKey: "hashProperty") as? String else { return false }
            guard let persistedState = states[identifier] else { return true }
            return persistedState == PersistedReportState.readyForSubmission.rawValue
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
            try backgroundContext.save()
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
    
    /// Removes the oldest record if the maximum number of records or total database size is exceeded
    /// Must be called only within a `performAndWaitThrowing` block
    /// - Throws: Any error from counting, removing records, or checking file size
    private func _removeOldestRecordIfNeededLocked() throws -> [UUID] {
        var removedIdentifiers = [UUID]()
        // check number of records
        if settings.maxRecordCount != BacktraceDatabaseSettings.unlimited {
            let removalCount = max(0, try _countResourcesLocked() + 1 - settings.maxRecordCount)
            if removalCount > 0 {
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
                let oldestResources = try _getResourcesLocked(sortDescriptors: sortDescriptors,
                                                              fetchLimit: removalCount)
                removedIdentifiers += _stageDeleteLocked(oldestResources)
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
                let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
                let oldestResource = try _getResourcesLocked(sortDescriptors: sortDescriptors,
                                                             fetchLimit: 1)
                removedIdentifiers += _stageDeleteLocked(oldestResource)
            }
        }
        return removedIdentifiers
    }

    func reconcileStorage() throws {
        guard !isShutdown else { return }
        try withTransaction {
            guard !isShutdown else { return }
            let terminalIdentifiers = try backgroundContext.performAndWaitThrowing {
                let states = try loadReportStatesLocked()
                let terminalResources = try _getResourcesLocked().filter { resource in
                    guard let identifier = resource.value(forKey: "hashProperty") as? String else {
                        return false
                    }
                    return states[identifier] == PersistedReportState.terminalAwaitingDeletion.rawValue
                }
                return try _deleteLocked(terminalResources)
            }
            cleanupResources(identifiers: terminalIdentifiers)

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
            cleanupWasDeferred = !reconcileReportStatesBestEffort(
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
        removeReportStatesBestEffort(identifiers: identifiers)
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

    private func loadReportStatesLocked() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: stateFileUrl.path) else { return [:] }
        let data = try Data(contentsOf: stateFileUrl)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let states = propertyList as? [String: String] else {
            throw FileError.invalidPropertyList
        }
        return states
    }

    private func storeReportStatesLocked(_ states: [String: String]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: states,
                                                      format: .binary,
                                                      options: 0)
        try data.write(to: stateFileUrl, options: .atomic)
    }

    private func quarantineCorruptReportStatesLocked() {
        guard FileManager.default.fileExists(atPath: stateFileUrl.path) else { return }
        let quarantineUrl = metadataDirectoryUrl.appendingPathComponent(
            "report-states.corrupt-\(UUID().uuidString).plist",
            isDirectory: false
        )
        do {
            try FileManager.default.moveItem(at: stateFileUrl, to: quarantineUrl)
        } catch {
            BacktraceLogger.warning("Could not quarantine corrupt report eligibility state; replacing it in place.")
        }

        guard let files = try? FileManager.default.contentsOfDirectory(at: metadataDirectoryUrl,
                                                                       includingPropertiesForKeys: [.contentModificationDateKey],
                                                                       options: [.skipsHiddenFiles]) else { return }
        let quarantined = files.filter { $0.lastPathComponent.hasPrefix("report-states.corrupt-") }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return left < right
            }
        for fileUrl in quarantined.dropLast(maximumCorruptReportStateArchives) {
            try? FileManager.default.removeItem(at: fileUrl)
        }
    }

    private func removeReportStatesBestEffort(identifiers: [UUID]) {
        guard !identifiers.isEmpty else { return }
        do {
            var states = try loadReportStatesLocked()
            identifiers.forEach { states.removeValue(forKey: $0.uuidString) }
            try storeReportStatesLocked(states)
        } catch {
            BacktraceLogger.warning("Deferred cleanup of persisted report eligibility state.")
        }
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

    private func reconcileReportStatesBestEffort(reportIdentifiers: Set<UUID>) -> Bool {
        do {
            var states = try loadReportStatesLocked()
            states = states.filter { key, _ in
                guard let identifier = UUID(uuidString: key) else { return false }
                return reportIdentifiers.contains(identifier)
            }
            try storeReportStatesLocked(states)
            return true
        } catch {
            // Fail closed: a damaged eligibility file must never make awaiting rows submit.
            BacktraceLogger.warning("Deferred report eligibility reconciliation.")
            return false
        }
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

    /// Drains only bounded local Core Data/file work after transport cancellation.
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

    private func withTransaction<T>(_ body: () throws -> T) rethrows -> T {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return try body()
    }
}
