import Foundation
import CoreData

extension Crash {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Crash> {
        return NSFetchRequest<Crash>(entityName: "Crash")
    }

    @objc(attachmentPaths)
    @NSManaged public var attachmentPaths: [String]?
    @objc(dateAdded)
    @NSManaged public var dateAdded: Date?
    @objc(hashProperty)
    @NSManaged public var hashProperty: String?
    @objc(reportData)
    @NSManaged public var reportData: Data?
    @objc(retryCount)
    @NSManaged public var retryCount: Int64

}
