import Foundation
import CoreData

/// Describes `PersistentStorable` Core Data
protocol PersistentStorable {
    associatedtype ManagedObjectType: NSManagedObject

    static var entityName: String { get }
    var identifier: UUID { get }
    var reportData: Data { get }
    var attachmentPaths: [String] { get set }
    var attributes: Attributes { get }

    init(managedObject: ManagedObjectType) throws
}

/// Persists `PersistentStorable` objects using Core Data
/// Manages concurrency by using a private-queue context and `performAndWaitThrowing` for all operations
final class PersistentRepository<Resource: PersistentStorable> {

    let backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings
    let url: URL
    
    /// Creates a new `PersistentRepository`
    /// - Parameter settings: BacktraceDatabaseSettings
    /// - Throws: `RepositoryError`
    init(settings: BacktraceDatabaseSettings) throws {
        self.settings = settings
        let momdName = "Model"
#if SWIFT_PACKAGE
        guard let modelURL = Bundle.module.url(forResource: momdName, withExtension: "momd") else {
            throw RepositoryError
                .persistentRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
        }
#else
        guard let bundleURL = Bundle(for: type(of: self)).url(forResource: "BacktraceResources", withExtension: "bundle"),
        let resourcesBundle = Bundle(url: bundleURL),
        let modelURL = resourcesBundle.url(forResource: momdName, withExtension: "momd") else {
            throw RepositoryError
                .persistentRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
        }
#endif
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
        try backgroundContext.performAndWaitThrowing {
            try _removeOldestRecordIfNeededLocked()
            
            guard let entity = NSEntityDescription.entity(forEntityName: Resource.entityName, in: backgroundContext) else {
                throw RepositoryError.canNotCreateEntityDescription
            }
            let newManagedObject = NSManagedObject(entity: entity, insertInto: backgroundContext)
            newManagedObject.setValue(resource.identifier.uuidString, forKey: "hashProperty")
            newManagedObject.setValue(resource.reportData, forKey: "reportData")
            newManagedObject.setValue(Date(), forKey: "dateAdded")
            newManagedObject.setValue(0, forKey: "retryCount")
            newManagedObject.setValue(resource.attachmentPaths, forKey: "attachmentPaths")
            try backgroundContext.save()
        }
        // File storage outside the Core Data backgroundContext (optional concurrency).
        // TODO: Verify AttributesStorage for concurrency
        try AttributesStorage.store(resource.attributes, fileName: resource.identifier.uuidString)
    }
    
    /// Deletes a resource from Core Data
    /// - Parameter resource: Resource to delete
    /// - Throws: Any error from fetching or deleting the records
    func delete(_ resource: Resource) throws {
        try backgroundContext.performAndWaitThrowing {
            let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
            let fetchRequestResults = try _getResourcesLocked(predicate: predicate, fetchLimit: 100)
            try _deleteLocked(fetchRequestResults)
        }
    }
    
    /// Fetches all stored resources from the database
    /// - Returns: [Resource]
    /// - Throws: Any error from the fetch request or object initialization
    func getAll() throws -> [Resource] {
        return try backgroundContext.performAndWaitThrowing {
            let resources = try _getResourcesLocked()
            return try resources.map(Resource.init)
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
            return try resources.map(Resource.init)
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
            return try latest.map(Resource.init)
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
            return try latest.map(Resource.init)
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
        try backgroundContext.performAndWaitThrowing {
            let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
            let fetchRequestResults = try _getResourcesLocked(predicate: predicate, fetchLimit: 1)
            
            guard let fetchedResult = fetchRequestResults.first,
                  let currentRetryCount: Int = fetchedResult.value(forKey: "retryCount") as? Int else {
                throw RepositoryError.resourceNotFound
            }
            // if exceeds limit, remove from db, otherwise just increment retryCount property
            if currentRetryCount >= limit {
                try _deleteLocked([fetchedResult])
            } else {
                // increment number of retires
                fetchedResult.setValue(currentRetryCount + 1, forKey: "retryCount")
                // update report data (could be modified)
                fetchedResult.setValue(resource.reportData, forKey: "reportData")
                try backgroundContext.save()
            }
        }
    }
    
    /// Deletes all stored resources
    /// - Throws: Any error from fetching or deleting the records
    func clear() throws {
        try backgroundContext.performAndWaitThrowing {
            let managedObjects = try _getResourcesLocked()
            try _deleteLocked(managedObjects)
        }
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
    private func _deleteLocked(_ managedObjects: [Resource.ManagedObjectType]) throws {
        managedObjects.forEach {
            if let fileName = $0.value(forKey: "hashProperty") as? String, let uuid = UUID(uuidString: fileName) {
                try? AttributesStorage.remove(fileName: uuid.uuidString)
            }
            backgroundContext.delete($0)
        }
        try backgroundContext.save()
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
    private func _removeOldestRecordIfNeededLocked() throws {
        // check number of records
        if settings.maxRecordCount != BacktraceDatabaseSettings.unlimited {
            while try _countResourcesLocked() + 1 > settings.maxRecordCount {
                try _removeOldestRecordLocked()
            }
        }
        
        // check database size
        if settings.maxDatabaseSize != BacktraceDatabaseSettings.unlimited {
            while try BacktraceFileManager.sizeOfFile(at: url) > settings.maxDatabaseSizeInBytes {
                let size = try BacktraceFileManager.sizeOfFile(at: url)
                BacktraceLogger.debug("Database size before removing last record: \(size)")
                try _removeOldestRecordLocked()
            }
        }
    }
    
    /// Removes the single oldest record (by `dateAdded`
    /// Must be called only within a `performAndWaitThrowing` block
    /// - Throws: Any error from fetching or deleting the record
    private func _removeOldestRecordLocked() throws {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
        let oldestResource = try _getResourcesLocked(sortDescriptors: sortDescriptors, fetchLimit: 1)
        try _deleteLocked(oldestResource)
    }
}
