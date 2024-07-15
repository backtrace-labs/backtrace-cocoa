import Foundation
import CoreData

extension Crash {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Crash> {
        return NSFetchRequest<Crash>(entityName: "Crash")
    }

    @NSManaged public var attachmentPaths: [String]?
    @NSManaged public var dateAdded: Date?
    @NSManaged public var hashProperty: String?
    @NSManaged public var reportData: Data?
    @NSManaged public var retryCount: Int64

}
