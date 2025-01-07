import Foundation
import CoreData

protocol PersistentStorable {
    associatedtype ManagedObjectType: NSManagedObject

    static var entityName: String { get }
    var identifier: UUID { get }
    var reportData: Data { get }
    var attachmentPaths: [String] { get set }
    var attributes: Attributes { get }

    init(managedObject: ManagedObjectType) async throws
}

final class PersistentRepository<Resource: PersistentStorable> {

    var backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings
    var url: URL

    init(settings: BacktraceDatabaseSettings) async throws {
        self.settings = settings

        let momdName = "Model"
        self.url = URL(fileURLWithPath: "")
        self.backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
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
        if #available(iOS 15.0, tvOS 15.0, macOS 10.13, *) {
            // Use NSPersistentContainer for iOS 15+, macOS 10.13+
            let persistentContainer = NSPersistentContainer(name: momdName, managedObjectModel: managedObjectModel)

            // Perform migration if needed
            try PersistentRepository.migration(
                coordinator: persistentContainer.persistentStoreCoordinator,
                storeDir: NSPersistentContainer.defaultDirectoryURL(),
                managedObject: managedObjectModel
            )

            // Load persistent stores using async/await
            let storeDescription = try await loadPersistentStoresAsync(container: persistentContainer)
            await BacktraceLogger.debug("Loaded persistent store: \(storeDescription)")

            guard let storeUrl = storeDescription.url else {
                throw RepositoryError.resourceNotFound
            }
            self.backgroundContext = persistentContainer.newBackgroundContext()
            self.url = storeUrl
            
            
            
//            let persistentContainer = NSPersistentContainer(name: momdName, managedObjectModel: managedObjectModel)
//            try PersistentRepository.migration(coordinator: persistentContainer.persistentStoreCoordinator,
//                                               storeDir: NSPersistentContainer.defaultDirectoryURL(),
//                                               managedObject: managedObjectModel)
//            let dispatch = DispatchSemaphore(value: 0)
//            var loadPersistentStoresError: Error?
//            var url: URL?
//            persistentContainer.loadPersistentStores { (storeDescription, error) in
//                BacktraceLogger.debug("Loaded persistent stores, store description: \(storeDescription)")
//                loadPersistentStoresError = error
//                url = storeDescription.url
//                dispatch.signal()
//            }
//            dispatch.wait()
//            if let error = loadPersistentStoresError {
//                throw RepositoryError.persistentRepositoryInitError(details: error.localizedDescription)
//            }
//            guard let storeUrl = url else { throw RepositoryError.resourceNotFound }
//            backgroundContext = persistentContainer.newBackgroundContext()
//            self.url = storeUrl
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
            await BacktraceLogger.debug("Loaded persistent stores, sore description: \(psc.persistentStores)")
            backgroundContext = managedObjectContext
            self.url = storeURL
        }
        try BacktraceFileManager.excludeFromBackup(url)
    }
    
    @available(iOS 15.0, macOS 12.0, *)
    private func loadPersistentStoresAsync(container: NSPersistentContainer) async throws -> NSPersistentStoreDescription {
        return try await withCheckedThrowingContinuation { continuation in
            container.loadPersistentStores { storeDescription, error in
                if let error = error {
                    continuation.resume(throwing: RepositoryError.persistentRepositoryInitError(details: error.localizedDescription))
                } else if let storeURL = storeDescription.url {
                    // unwrap optional
                    let storeCopy = NSPersistentStoreDescription(url: storeURL)
                    storeCopy.configuration = storeDescription.configuration
                    storeCopy.type = storeDescription.type
                    continuation.resume(returning: storeCopy)
                } else {
                    // URL is nil
                    continuation.resume(throwing: RepositoryError.persistentRepositoryInitError(details: "Persistent store URL is nil."))
                }
            }
        }
    }


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

    func save(_ resource: Resource) async throws {
        try await removeOldestRecordIfNeeded()

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
        try await AttributesStorage.store(resource.attributes, fileName: resource.identifier.uuidString)
    }

    func delete(_ resource: Resource) async throws {
        let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
        let fetchRequestResults = try getResources(predicate: predicate, fetchLimit: 100)
        try await delete(managedObjects: fetchRequestResults)
    }

    /// Convenience method for deleting reports. Only this method should be used for deleting objects from
    /// database context.
    ///
    /// - Parameter managedObjects: Managed objects to delete
    private func delete(managedObjects: [Resource.ManagedObjectType]) async throws {
        for managedObject in managedObjects {
            if let fileName = managedObject.value(forKey: "hashProperty") as? String,
               let uuid = UUID(uuidString: fileName) {
                // Use await for the async call to remove attributes
                try await AttributesStorage.remove(fileName: uuid.uuidString)
            }
            backgroundContext.delete(managedObject)
        }

        // Save changes to the context
        try backgroundContext.save()
    }
    
    func getAll() async throws -> [Resource] {
        let managedObjects = try getResources()
        return try await managedObjects.asyncMap { try await Resource(managedObject: $0) }
    }

    func get(
        sortDescriptors: [NSSortDescriptor]? = nil,
        predicate: NSPredicate? = nil,
        fetchLimit: Int? = nil
    ) async throws -> [Resource] {
        let managedObjects = try getResources(sortDescriptors: sortDescriptors, predicate: predicate, fetchLimit: fetchLimit)
        return try await managedObjects.asyncMap { try await Resource(managedObject: $0) }
    }

    func getLatest(count: Int = 1) async throws -> [Resource] {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
        let latestManagedObjects = try getResources(sortDescriptors: sortDescriptors, fetchLimit: count)
        return try await latestManagedObjects.asyncMap { try await Resource(managedObject: $0) }
    }

    func getOldest(count: Int = 1) async throws -> [Resource] {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
        let oldestManagedObjects = try getResources(sortDescriptors: sortDescriptors, fetchLimit: count)
        return try await oldestManagedObjects.asyncMap { try await Resource(managedObject: $0) }
    }

    func incrementRetryCount(_ resource: Resource, limit: Int) async throws {
        let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
        let fetchRequestResults = try getResources(predicate: predicate, fetchLimit: 1)

        guard let fetchedResult = fetchRequestResults.first,
            let currentRetryCount: Int = fetchedResult.value(forKey: "retryCount") as? Int else {
                throw RepositoryError.resourceNotFound
        }
        // if exceeds limit, remove from db, otherwise just increment retryCount property
        if currentRetryCount >= limit {
            try await delete(managedObjects: [fetchedResult])
        } else {
            // increment number of retries
            fetchedResult.setValue(currentRetryCount + 1, forKey: "retryCount")
            // update report data (could be modified)
            fetchedResult.setValue(resource.reportData, forKey: "reportData")
            if #available(iOS 15.0, *) {
                try await backgroundContext.perform {
                    try self.backgroundContext.save()
                }
            } else {
                try backgroundContext.save()
            }
        }
    }

    func clear() async throws {
        let managedObjects = try getResources()
        try await delete(managedObjects: managedObjects)
    }

    /// Remove oldest result if max number of records is exceeded or total database size is exceeded.
    private func removeOldestRecordIfNeeded() async throws {
        if settings.maxRecordCount != BacktraceDatabaseSettings.unlimited {
            // check number of records
            while try countResources() + 1 > settings.maxRecordCount {
                try await removeOldestRecord()
            }
        }

        if settings.maxDatabaseSize != BacktraceDatabaseSettings.unlimited {
            // check database size
            while try BacktraceFileManager.sizeOfFile(at: url) > settings.maxDatabaseSizeInBytes {
                let size = try BacktraceFileManager.sizeOfFile(at: url)
                await BacktraceLogger.debug("Database size before removing last record: \(size)")
                try await removeOldestRecord()
            }
        }
    }

    private func removeOldestRecord() async throws {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
        let oldestResource = try getResources(sortDescriptors: sortDescriptors, fetchLimit: 1)
        try await delete(managedObjects: oldestResource)
    }

    func countResources() throws -> Int {
        let resourcesCountRequest = NSFetchRequest<Resource.ManagedObjectType>(entityName: Resource.entityName)
        return try backgroundContext.count(for: resourcesCountRequest)
    }

    private func getResources(sortDescriptors: [NSSortDescriptor]? = nil,
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
}

extension Array {
    /// A helper method to map an array using an async closure.
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results = [T]()
        results.reserveCapacity(count)
        for element in self {
            let result = try await transform(element)
            results.append(result)
        }
        return results
    }
}
