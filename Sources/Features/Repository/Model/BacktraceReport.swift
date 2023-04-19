import Foundation
import CrashReporter

/// Model represents single crash report which can be send to Backtrace services.
@objc final public class BacktraceReport: NSObject {

    /// Encoded informations about report like stack trace etc.
    @objc public let reportData: Data

    let plCrashReport: PLCrashReport
    let identifier: UUID

    /// Array of files paths attached to the report.
    @objc public var attachmentPaths: [String]

    /// `Attributes` attached to the report.
    @objc public var attributes: Attributes

    init(report: Data, attributes: Attributes, attachmentPaths: [String]) throws {
        self.plCrashReport = try PLCrashReport(data: report)
        reportData = report
        identifier = UUID()
        self.attachmentPaths = attachmentPaths
        self.attributes = attributes
        super.init()
    }

    init(managedObject: Crash) throws {
        guard let reportData = managedObject.reportData,
            let identifierString = managedObject.hashProperty,
            let attachmentPaths = managedObject.attachmentPaths,
            let identifier = UUID(uuidString: identifierString) else {
                throw RepositoryError.canNotCreateEntityDescription
        }
        self.reportData = reportData
        self.plCrashReport = try PLCrashReport(data: reportData)
        self.identifier = identifier
        self.attachmentPaths = attachmentPaths
        self.attributes = (try? AttributesStorage.retrieve(fileName: identifier.uuidString)) ?? [:]
        super.init()
    }
}

// MARK: - PersistentStorable
extension BacktraceReport: PersistentStorable {
    typealias ManagedObjectType = Crash

    static var entityName: String { return "Crash" }
}
