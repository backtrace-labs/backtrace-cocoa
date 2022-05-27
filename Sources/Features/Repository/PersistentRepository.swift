import Foundation
import CoreData

protocol PersistentStorable {
    associatedtype ManagedObjectType: NSManagedObject

    static var entityName: String { get }
    var identifier: UUID { get }
    var reportData: Data { get }
    var attachmentPaths: [String] { get set }
    var attributes: Attributes { get }

    init(managedObject: ManagedObjectType) throws
}

final class PersistentRepository<Resource: PersistentStorable> {

    let backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings

    let url: URL

    init(settings: BacktraceDatabaseSettings) throws {
        self.settings = settings

        let momdName = "Model"
        var modelURL: URL?
#if SWIFT_PACKAGE
        if let strURL = Bundle.module.path(forResource:momdName, ofType:"momd") {
            modelURL = URL(string: strURL)
        }
#endif
        if modelURL == nil {
            modelURL = Bundle(for: type(of: self)).url(forResource: momdName, withExtension: "momd")
        }
        guard let modelURL = modelURL else {
            throw RepositoryError
                .persistentRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
        }
        
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

    func save(_ resource: Resource) throws {
        try removeOldestRecordIfNeeded()

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
        try AttributesStorage.store(resource.attributes, fileName: resource.identifier.uuidString)
    }

    func delete(_ resource: Resource) throws {
        let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
        let fetchRequestResults = try getResources(predicate: predicate, fetchLimit: 100)
        try delete(managedObjects: fetchRequestResults)
    }

    /// Convenience method for deleting reports. Only this method should be used for deleting objects from
    /// database context.
    ///
    /// - Parameter managedObjects: Managed objects to delete
    private func delete(managedObjects: [Resource.ManagedObjectType]) throws {
        managedObjects.forEach {
            if let fileName = $0.value(forKey: "hashProperty") as? String, let uuid = UUID(uuidString: fileName) {
                try? AttributesStorage.remove(fileName: uuid.uuidString)
            }
            backgroundContext.delete($0)
        }
        try backgroundContext.save()
    }

    func getAll() throws -> [Resource] {
        return try getResources().map(Resource.init)
    }

    func get(sortDescriptors: [NSSortDescriptor]? = nil,
             predicate: NSPredicate? = nil,
             fetchLimit: Int? = nil) throws -> [Resource] {
        return try getResources(sortDescriptors: sortDescriptors, predicate: predicate, fetchLimit: fetchLimit)
            .map(Resource.init)
    }

    func getLatest(count: Int = 1) throws -> [Resource] {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
        let latest = try getResources(sortDescriptors: sortDescriptors, fetchLimit: count)
        return try latest.map(Resource.init)
    }

    func getOldest(count: Int = 1) throws -> [Resource] {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
        let latest = try getResources(sortDescriptors: sortDescriptors, fetchLimit: count)
        return try latest.map(Resource.init)
    }

    func incrementRetryCount(_ resource: Resource, limit: Int) throws {
        let predicate = NSPredicate(format: "hashProperty==%@", resource.identifier.uuidString)
        let fetchRequestResults = try getResources(predicate: predicate, fetchLimit: 1)

        guard let fetchedResult = fetchRequestResults.first,
            let currentRetryCount: Int = fetchedResult.value(forKey: "retryCount") as? Int else {
                throw RepositoryError.resourceNotFound
        }
        // if exceeds limit, remove from db, otherwise just increment retryCount property
        if currentRetryCount >= limit {
            try delete(managedObjects: [fetchedResult])
        } else {
            // increment number of retires
            fetchedResult.setValue(currentRetryCount + 1, forKey: "retryCount")
            // update report data (could be modified)
            fetchedResult.setValue(resource.reportData, forKey: "reportData")
            try backgroundContext.save()
        }
    }

    func clear() throws {
        let managedObjects = try getResources()
        try delete(managedObjects: managedObjects)
    }

    /// Remove oldest result if max number of records is exceeded or total database size is exceeded.
    private func removeOldestRecordIfNeeded() throws {
        if settings.maxRecordCount != BacktraceDatabaseSettings.unlimited {
            // check number of records
            while try countResources() + 1 > settings.maxRecordCount {
                try removeOldestRecord()
            }
        }

        if settings.maxDatabaseSize != BacktraceDatabaseSettings.unlimited {
            // check database size
            while try BacktraceFileManager.sizeOfFile(at: url) > settings.maxDatabaseSizeInBytes {
                let size = try BacktraceFileManager.sizeOfFile(at: url)
                BacktraceLogger.debug("Database size before removing last record: \(size)")
                try removeOldestRecord()
            }
        }
    }

    private func removeOldestRecord() throws {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
        let oldestResource = try getResources(sortDescriptors: sortDescriptors, fetchLimit: 1)
        try delete(managedObjects: oldestResource)
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
