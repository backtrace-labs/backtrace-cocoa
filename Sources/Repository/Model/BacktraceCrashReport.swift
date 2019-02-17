import Foundation
import Backtrace_PLCrashReporter

@objc final public class BacktraceCrashReport: NSObject {
    
    let reportData: Data
    let plCrashReport: PLCrashReport
    let identifier: UUID
    
    init(report: Data) throws {
        self.plCrashReport = try PLCrashReport(data: report)
        reportData = report
        identifier = UUID()
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
        super.init()
    }
}
// MARK: - PersistentStorable
extension BacktraceCrashReport: PersistentStorable {
    typealias ManagedObjectType = Crash
    
    static var entityName: String { return "Crash" }
}
