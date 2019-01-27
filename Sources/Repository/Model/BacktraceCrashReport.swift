import Foundation

struct BacktraceCrashReport {
    //swiftlint:disable legacy_hashing
    let hashValue: Int
    //swiftlint:enable legacy_hashing
    let reportData: Data

    init(report: Data, hashValue: Int? = nil) {
        self.reportData = report
        self.hashValue = hashValue ?? UUID().hashValue
    }
}

extension BacktraceCrashReport: Equatable {

}

// MARK: - PersistentStorable
extension BacktraceCrashReport: PersistentStorable {
    typealias ManagedObjectType = Crash
    
    var hashProperty: Int { return hashValue }
    static var entityName: String { return "Crash" }
    
    init(managedObject: Crash) throws {
        self.hashValue = Int(managedObject.hashProperty)
        guard let reportData = managedObject.reportData else {
            throw RepositoryError.canNotCreateEntityDescription
        }
        self.reportData = reportData
    }
}
