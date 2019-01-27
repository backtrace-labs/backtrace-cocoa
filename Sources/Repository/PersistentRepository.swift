import Foundation
import CoreData

protocol PersistentStorable {
    associatedtype ManagedObjectType: NSManagedObject
    
    static var entityName: String { get }
    var hashProperty: Int { get }
    var reportData: Data { get }
    
    init(managedObject: ManagedObjectType) throws
}

class PersistentRepository<Resource: PersistentStorable> {
    
    let backgroundContext: NSManagedObjectContext
    let settings: BacktraceDatabaseSettings
    
    let url: URL
    
    init(settings: BacktraceDatabaseSettings) throws {
        self.settings = settings
        
        let momdName = "Model"
        guard let modelURL = Bundle(for: type(of: self)).url(forResource: momdName, withExtension: "momd") else {
            throw RepositoryError.persistenRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
        }
        guard let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            // swiftlint:disable line_length
            throw RepositoryError.persistenRepositoryInitError(details: "Couldn't create `NSManagedObjectModel` using model file at url: \(modelURL)")
            // swiftlint:enable line_length
        }
        let psc = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = psc
        let storeUrl = try PersistentRepository.storeUrl(modelName: momdName)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeUrl, options: nil)
        BacktraceLogger.debug("Loaded persistent stores, sore description: \(psc.persistentStores)")
        backgroundContext = managedObjectContext
        url = storeUrl
    }
    
    private class func storeUrl(modelName: String) throws -> URL {
        guard let docURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RepositoryError.persistenRepositoryInitError(details: "Unable to resolve document directory")
        }
        let storeURL = docURL.appendingPathComponent("\(modelName).sqlite")
        return storeURL
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
        newManagedObject.setValue(resource.hashProperty, forKey: "hashProperty")
        newManagedObject.setValue(resource.reportData, forKey: "reportData")
        newManagedObject.setValue(Date(), forKey: "dateAdded")
        newManagedObject.setValue(0, forKey: "retryCount")
        try backgroundContext.save()
        
        let records = try countResources()
        BacktraceLogger.debug("Number of records before removing last record: \(records)")
    }
    
    func delete(_ resource: Resource) throws {
        let predicate = NSPredicate(format: "hashProperty==\(resource.hashProperty)")
        let fetchRequestResults = try getResources(predicate: predicate, fetchLimit: 1)
        try delete(managedObjects: fetchRequestResults)
    }
    
    private func delete(managedObjects: [Resource.ManagedObjectType]) throws {
        managedObjects.forEach { backgroundContext.delete($0) }
        try backgroundContext.save()
    }
    
    func getAll() throws -> [Resource] {
        return try getResources().map(Resource.init)
    }
    
    func get(sortDescriptors: [NSSortDescriptor]? = nil, predicate: NSPredicate? = nil) throws -> [Resource] {
        return try getResources(sortDescriptors: sortDescriptors, predicate: predicate).map(Resource.init)
    }
    
    func getLatest() throws -> Resource? {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
        let latest = try getResources(sortDescriptors: sortDescriptors, fetchLimit: 1)
        return try latest.map(Resource.init).first
    }
    
    func getOldest() throws -> Resource? {
        let sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: true)]
        let latest = try getResources(sortDescriptors: sortDescriptors, fetchLimit: 1)
        return try latest.map(Resource.init).first
    }
    
    func incrementRetryCount(_ resource: Resource, limit: Int) throws {
        // TODO: Remove all associated files stored on disk.
        let predicate = NSPredicate(format: "hashProperty==\(resource.hashProperty)")
        let fetchRequestResults = try getResources(predicate: predicate, fetchLimit: 1)
        
        guard let fetchedResult = fetchRequestResults.first,
            let currentRetryCount: Int = fetchedResult.value(forKey: "retryCount") as? Int else {
                throw RepositoryError.resourceNotFound
        }
        // if exceeds limit, remove from db, otherwise just increment retryCount property
        if currentRetryCount >= limit {
            backgroundContext.delete(fetchedResult)
        } else {
            fetchedResult.setValue(currentRetryCount + 1, forKey: "retryCount")
        }
        try backgroundContext.save()
    }
    
    func clear() throws {
        let objects = try getResources()
        objects.forEach(backgroundContext.delete)
    }
    
    /// Remove oldest result if max number of records is exceeded or total database size is exceeded.
    private func removeOldestRecordIfNeeded() throws {
        // TODO: Make internal and remove all associated files stored on disk.
        if settings.maxRecordCount != BacktraceDatabaseSettings.unlimited {
            // check number of records
            while try countResources() + 1 > settings.maxRecordCount {
                var records = try countResources()
                BacktraceLogger.debug("Number of records before removing last record: \(records)")
                try removeOldestRecord()
                records = try countResources()
                BacktraceLogger.debug("Number of records before removing last record: \(records)")
            }
        }
        
        if settings.maxDatabaseSize != BacktraceDatabaseSettings.unlimited {
            // check database size
            while try BacktraceFileManager.sizeOfFile(at: url) > settings.maxDatabaseSize {
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
        let resourcesCountRequet = NSFetchRequest<Resource.ManagedObjectType>(entityName: Resource.entityName)
        return try backgroundContext.count(for: resourcesCountRequet)
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
