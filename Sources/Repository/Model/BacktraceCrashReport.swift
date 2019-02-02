import Foundation
import Backtrace_PLCrashReporter

@objc final public class BacktraceCrashReport: NSObject {
    
    let reportData: Data
    let plCrashReport: PLCrashReport
    
    init(report: Data) throws {
        self.plCrashReport = try PLCrashReport(data: report)
        reportData = report
        super.init()
    }
    
    init(managedObject: Crash) throws {
        guard let reportData = managedObject.reportData else {
            throw RepositoryError.canNotCreateEntityDescription
        }
        self.reportData = reportData
        self.plCrashReport = try PLCrashReport(data: reportData)
        super.init()
    }
}
// MARK: - PersistentStorable
extension BacktraceCrashReport: PersistentStorable {
    typealias ManagedObjectType = Crash
    
    var hashProperty: Int {
        let uuid: UUID
        if var cfUuid = plCrashReport.uuidRef {
            uuid = withUnsafePointer(to: &cfUuid) { (cfUuidPointer) -> UUID in
                return cfUuidPointer
                    .withMemoryRebound(to: UUID.self, capacity: MemoryLayout<UUID>.size, { (uuidPointer) -> UUID in
                    return uuidPointer.pointee
                })
            }
        } else {
            uuid = UUID()
        }
        return uuid.hashValue
    }
    static var entityName: String { return "Crash" }
}
