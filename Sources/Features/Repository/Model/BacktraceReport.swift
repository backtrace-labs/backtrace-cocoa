import Foundation

#if BACKTRACE_UNITY_PREFIXED_PLCRASHREPORTER
import BTUnityCrashReporter
#else
import CrashReporter
#endif

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

    init(report: Data,
         attributes: Attributes,
         attachmentPaths: [String],
         identifier: UUID = UUID()) throws {
        self.plCrashReport = try PLCrashReport(data: report)
        reportData = report
        self.identifier = identifier
        self.attachmentPaths = attachmentPaths
        self.attributes = attributes
        super.init()
        
        self.extendCrashAttributes()
    }

    convenience init(pendingReport report: Data,
                     attributes: Attributes,
                     attachmentPaths: [String]) throws {
        try self.init(report: report,
                      attributes: attributes,
                      attachmentPaths: attachmentPaths,
                      identifier: BacktraceReportIdentifier.pendingReportIdentifier(for: report))
    }
    
    init(managedObject: Crash, metadataDirectoryUrl: URL?) throws {
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
        self.attributes = (try? AttributesStorage.retrieve(fileName: identifier.uuidString,
                                                           directoryUrl: metadataDirectoryUrl))
            ?? (try? AttributesStorage.retrieve(fileName: identifier.uuidString))
            ?? [:]
        
        super.init()
        
        self.extendCrashAttributes()
    }
}

// MARK: - PersistentStorable
extension BacktraceReport: PersistentStorable {
    typealias ManagedObjectType = Crash

    static var entityName: String { return "Crash" }
    
    private func extendCrashAttributes() {
        guard let customData = self.plCrashReport.customData else {
            return
           }
        
          if let attributes = try? JSONSerialization.jsonObject(with: customData, options: []) as? [String: Any] {
              self.attributes += attributes
          } else {
              return
          }
    }

    
}
