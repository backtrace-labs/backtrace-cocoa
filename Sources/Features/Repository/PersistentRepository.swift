import Foundation
import CoreData

private final class BacktraceResourceBundleToken: NSObject {}

/// Describes `PersistentStorable` Core Data
protocol PersistentStorable: AnyObject {
    associatedtype ManagedObjectType: NSManagedObject

    static var entityName: String { get }
    var identifier: UUID { get }
    var reportData: Data { get }
    var attachmentPaths: [String] { get set }
    var attributes: Attributes { get }

    init(managedObject: ManagedObjectType, metadataDirectoryUrl: URL?) throws
}

/// Persists `PersistentStorable` objects using Core Data
/// Manages concurrency by using a private-queue context and `performAndWaitThrowing` for all operations
final class PersistentRepository<Resource: PersistentStorable> {

    let backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings
    let url: URL
    let attachmentStore: RepositoryAttachmentStore
    let metadataDirectoryUrl: URL
    
    /// Creates a new `PersistentRepository`
    /// - Parameter settings: BacktraceDatabaseSettings
    /// - Throws: `RepositoryError`
    init(settings: BacktraceDatabaseSettings) throws {
        self.settings = settings
        let momdName = "Model"
        guard let modelURL = Self.resolveModelUrl(modelName: momdName) else {
            throw RepositoryError
                .persistentRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
        }
        BacktraceLogger.debug("Resolved Core Data model at: \(modelURL.path)")
        guard let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            // swiftlint:disable line_length
            throw RepositoryError.persistentRepositoryInitError(details: "Couldn't create `NSManagedObjectModel` using model file at url: \(modelURL)")
            // swiftlint:enable line_length
        }
        if #available(iOS 10.0, tvOS 10.0, macOS 10.12, *) {
            let persistentContainer = NSPersistentContainer(name: momdName, managedObjectModel: managedObjectModel)
            try PersistentRepository.migration(coordinator: persistentContainer.persistentStoreCoordinator,
                                               storeDir: NSPersistentContainer.defaultDirectoryURL(),
                                               managedObject: managedObjectModel)
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
                throw RepositoryError.persistentRepositoryInitError(details: error.localizedDescription)
            }
            guard let storeUrl = url else { throw RepositoryError.resourceNotFound }
            backgroundContext = persistentContainer.newBackgroundContext()
            self.url = storeUrl
        } else {
            let psc = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
            let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            managedObjectContext.persistentStoreCoordinator = psc
            guard let storeDir =
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).last else {
                throw RepositoryError.persistentRepositoryInitError(details: "Unable to resolve document directory") }
            try PersistentRepository.migration(coordinator: psc, storeDir: storeDir, managedObject: managedObjectModel)
            let storeURL = storeDir.appendingPathComponent("Model.sqlite")
            try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            BacktraceLogger.debug("Loaded persistent stores, sore description: \(psc.persistentStores)")
            backgroundContext = managedObjectContext
            url = storeURL
        }
        try BacktraceFileManager.excludeFromBackup(url)
        self.attachmentStore = try RepositoryAttachmentStore(databaseUrl: url)
        self.metadataDirectoryUrl = url.deletingLastPathComponent()
            .appendingPathComponent("BacktraceReportMetadata", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: metadataDirectoryUrl,
                                                withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.none])
        try? BacktraceFileManager.excludeFromBackup(metadataDirectoryUrl)
        try reconcileStorage()
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
        try save(resource, requiresCompleteAttachments: false)
    }

    /// Durably saves a pending crash before its PLCrashReporter source may be purged.
    ///
    /// Unlike ordinary retry persistence, this rejects a first ingestion when any declared attachment cannot be copied.
    /// An idempotent repeat may reuse a complete repository-owned generation that was committed by an earlier ingestion of the same report identifier.
    func savePending(_ resource: Resource) throws {
        try save(resource, requiresCompleteAttachments: true)
    }

    private func save(_ resource: Resource, requiresCompleteAttachments: Bool) throws {
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
                                                              reportIdentifier: resource.identifier)
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

        guard !requiresCompleteAttachments || storedAttachments.isComplete else {
            attachmentStore.rollback(storedAttachments)
            throw RepositoryAttachmentStoreError.incompleteAttachmentStaging
        }

        var persistedAttributes = (try? AttributesStorage.retrieve(
            fileName: resource.identifier.uuidString,
            directoryUrl: metadataDirectoryUrl
        )) ?? [:]
        persistedAttributes += resource.attributes
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
                try backgroundContext.save()
                return identifiersToClean
            }
        } catch {
            attachmentStore.rollback(storedAttachments)
            restoreAttributes(previousAttributesData, config: attributesConfig)
            throw error
        }

        resource.attachmentPaths = storedAttachments.paths
        cleanupResources(identifiers: evictedIdentifiers)
    }
    
    /// Deletes a resource from Core Data
    /// - Parameter resource: Resource to delete
    /// - Throws: Any error from fetching or deleting the records
    func delete(_ resource: Resource) throws {
        let deletedIdentifiers = try backgroundContext.performAndWaitThrowing {
            let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
            let fetchRequestResults = try _getResourcesLocked(predicate: predicate, fetchLimit: 100)
            return try _deleteLocked(fetchRequestResults)
        }
        cleanupResources(identifiers: deletedIdentifiers)
    }
    
    /// Fetches all stored resources from the database
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getAll() throws -> [Resource] {
        return try backgroundContext.performAndWaitThrowing {
            let resources = try _getResourcesLocked()
            return try resources.map { try Resource(managedObject: $0,
                                                    metadataDirectoryUrl: metadataDirectoryUrl) }
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
        return try backgroundContext.performAndWaitThrowing {
            let resources = try _getResourcesLocked(sortDescriptors: sortDescriptors, predicate: predicate, fetchLimit: fetchLimit)
            return try resources.map { try Resource(managedObject: $0,
                                                    metadataDirectoryUrl: metadataDirectoryUrl) }
        }
    }
    
    /// Fetches the newest (by `dateAdded`) resources
    /// - Parameter count: Int : Default`1`
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getLatest(count: Int = 1) throws -> [Resource] {
        return try backgroundContext.performAndWaitThrowing {
            let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
            let latest = try _getResourcesLocked(sortDescriptors: sortDescriptors, fetchLimit: count)
            return try latest.map { try Resource(managedObject: $0,
                                                 metadataDirectoryUrl: metadataDirectoryUrl) }
        }
    }
    
    /// Fetches the oldest (by `dateAdded`) resources
    /// - Parameter count: Int : Default`1`
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getOldest(count: Int = 1) throws -> [Resource] {
        return try backgroundContext.performAndWaitThrowing {
            let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
            let latest = try _getResourcesLocked(sortDescriptors: sortDescriptors, fetchLimit: count)
            return try latest.map { try Resource(managedObject: $0,
                                                 metadataDirectoryUrl: metadataDirectoryUrl) }
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
                try backgroundContext.save()
                return []
            }
        }
        cleanupResources(identifiers: deletedIdentifiers)
    }
    
    /// Deletes all stored resources
    /// - Throws: Any error from fetching or deleting the records
    func clear() throws {
        let deletedIdentifiers = try backgroundContext.performAndWaitThrowing {
            let managedObjects = try _getResourcesLocked()
            return try _deleteLocked(managedObjects)
        }
        cleanupResources(identifiers: deletedIdentifiers)
    }
    
    ///  Returns the total count of resources in the database
    /// - Returns: Int: The number of resources
    func countResources() throws -> Int {
        try backgroundContext.performAndWaitThrowing {
            try _countResourcesLocked()
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
    
    /// Convenience method for deleting the specified managed objects
    /// Must be called only within a `performAndWaitThrowing` block
    ///
    /// - Parameter managedObjects: Managed objects to delete
    /// - Throws: Any error from `save()`.
    private func _deleteLocked(_ managedObjects: [Resource.ManagedObjectType]) throws -> [UUID] {
        let identifiers = managedObjects.compactMap {
            ($0.value(forKey: "hashProperty") as? String).flatMap(UUID.init(uuidString:))
        }
        managedObjects.forEach {
            backgroundContext.delete($0)
        }
        try backgroundContext.save()
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
            while try _countResourcesLocked() + 1 > settings.maxRecordCount {
                removedIdentifiers += try _removeOldestRecordLocked()
            }
        }
        
        // check database size
        if settings.maxDatabaseSize != BacktraceDatabaseSettings.unlimited {
            while try BacktraceFileManager.sizeOfFile(at: url) > settings.maxDatabaseSizeInBytes {
                let size = try BacktraceFileManager.sizeOfFile(at: url)
                BacktraceLogger.debug("Database size before removing last record: \(size)")
                removedIdentifiers += try _removeOldestRecordLocked()
            }
        }
        return removedIdentifiers
    }
    
    /// Removes the single oldest record (by `dateAdded`
    /// Must be called only within a `performAndWaitThrowing` block
    /// - Throws: Any error from fetching or deleting the record
    private func _removeOldestRecordLocked() throws -> [UUID] {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
        let oldestResource = try _getResourcesLocked(sortDescriptors: sortDescriptors, fetchLimit: 1)
        return try _deleteLocked(oldestResource)
    }

    func reconcileStorage() throws {
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
        try attachmentStore.reconcile(referencedAttachmentPaths: storageSnapshot.attachmentPaths)
        try reconcileMetadataStorage(reportIdentifiers: storageSnapshot.identifiers)
    }

    private func cleanupResources(identifiers: [UUID]) {
        for identifier in Set(identifiers) {
            do {
                try AttributesStorage.remove(fileName: identifier.uuidString,
                                             directoryUrl: metadataDirectoryUrl)
                // Remove the pre-2.1.1 cache-backed sidecar after a repository row is deleted.
                try? AttributesStorage.remove(fileName: identifier.uuidString)
            } catch {
                BacktraceLogger.warning("Unable to remove persisted attributes for \(identifier): \(error)")
            }
            do {
                try attachmentStore.removeAttachments(for: identifier)
            } catch {
                BacktraceLogger.warning("Unable to remove persisted attachments for \(identifier): \(error)")
            }
        }
    }

    private func reconcileMetadataStorage(reportIdentifiers: Set<UUID>) throws {
        for identifier in reportIdentifiers {
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
        }

        let files = try FileManager.default.contentsOfDirectory(at: metadataDirectoryUrl,
                                                                includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles])
        for fileUrl in files where fileUrl.pathExtension == "plist" {
            guard let identifier = UUID(uuidString: fileUrl.deletingPathExtension().lastPathComponent),
                  !reportIdentifiers.contains(identifier) else { continue }
            try FileManager.default.removeItem(at: fileUrl)
        }
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
            BacktraceLogger.error("Unable to roll back attributes at \(config.fileUrl.path): \(error)")
        }
    }
}
