import Foundation
import Backtrace_PLCrashReporter

@objc final public class BacktraceReport: NSObject {
    
    let reportData: Data
    let plCrashReport: PLCrashReport
    let identifier: UUID
    var attributes: Attributes
    
    init(report: Data, attributes: Attributes) throws {
        self.plCrashReport = try PLCrashReport(data: report)
        reportData = report
        identifier = UUID()
        self.attributes = attributes
        super.init()
    }
    
    init(managedObject: Crash) throws {
        guard let reportData = managedObject.reportData,
        let identifierString = managedObject.hashProperty,
        let identifier = UUID(uuidString: identifierString) else {
            throw RepositoryError.canNotCreateEntityDescription
        }
        self.reportData = reportData
        self.plCrashReport = try PLCrashReport(data: reportData)
        self.identifier = identifier
        self.attributes = (try? AttributesStorage.retrieve(fileName: identifier.uuidString)) ?? [:]
        super.init()
    }
}

// MARK: - PersistentStorable
extension BacktraceReport: PersistentStorable {
    typealias ManagedObjectType = Crash
    
    static var entityName: String { return "Crash" }
}
