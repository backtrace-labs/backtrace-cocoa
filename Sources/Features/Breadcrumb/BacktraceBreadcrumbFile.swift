import Foundation

enum BacktraceBreadcrumbFileError: Error {
    case invalidFormat
}

@objc class BacktraceBreadcrumbFile: NSObject, @unchecked Sendable  {

    private static let minimumQueueFileSizeBytes = 4096
    private let maximumIndividualBreadcrumbSize: Int
    private let maxQueueFileSizeBytes: Int
    private let queue: Queue<BreadcrumbRecord>
    private let breadcrumbLogURL: URL

    public init(_ breadcrumbSettings: BacktraceBreadcrumbSettings) throws {
        self.breadcrumbLogURL = try breadcrumbSettings.getBreadcrumbLogPath()
        self.queue = Queue<BreadcrumbRecord>()
        self.maximumIndividualBreadcrumbSize = breadcrumbSettings.maxIndividualBreadcrumbSizeBytes
        self.maxQueueFileSizeBytes = breadcrumbSettings.maxQueueFileSizeBytes

        super.init()
    }

    func addBreadcrumb(_ breadcrumb: [String: Any]) async -> Bool {
        guard let breadcrumbJsonData = try? JSONSerialization.data(withJSONObject: breadcrumb) else {
            await BacktraceLogger.warning("Error when converting breadcrumb to data")
            return false
        }
        guard let breadcrumbJsonString = String(data: breadcrumbJsonData, encoding: .utf8) else {
            await BacktraceLogger.warning("Error when converting breadcrumb to string")
            return false
        }
        let breadcrumbSize = breadcrumbJsonData.count
        // Check if breadcrumb size is larger than the maximum specified
        if breadcrumbSize > maximumIndividualBreadcrumbSize {
            await BacktraceLogger.warning(
                "Discarding breadcrumb that was larger than the maximum specified (\(maximumIndividualBreadcrumbSize).")
            return false
        }
        // Enqueue the breadcrumb record
        let queueBreadcrumb = BreadcrumbRecord(size: breadcrumbSize, json: breadcrumbJsonString)
        await queue.enqueue(queueBreadcrumb)
        
        // Prepare breadcrumbs array for logging
        var size = 0
        var breadcrumbsArray = [String]()
        let records = await queue.allElements().reversed()
        
        for record in records {
            if size + record.size > maxQueueFileSizeBytes {
                break
            }
            breadcrumbsArray.append(record.json)
            size += record.size
        }
        
        let breadcrumbString = "[\(breadcrumbsArray.joined(separator: ","))]"
        await writeBreadcrumbToLogFile(breadcrumb: breadcrumbString, at: breadcrumbLogURL)
        
        return true
    }

    func clear() async -> Bool {
        await self.queue.clear()
        await self.clearBreadcrumbLogFile(at: self.breadcrumbLogURL)
        return true
    }
}

extension BacktraceBreadcrumbFile {
    
    func writeBreadcrumbToLogFile(breadcrumb: String, at breadcrumbLogURL: URL) async {
        do {
            try breadcrumb.write(to: breadcrumbLogURL, atomically: true, encoding: .utf8)
        } catch {
            await BacktraceLogger.warning("Error writing breadcrumb to log file at: \(breadcrumbLogURL) - \(error.localizedDescription)")
        }
    }

    func clearBreadcrumbLogFile(at breadcrumbLogURL: URL) async {
        do {
            try "".write(to: breadcrumbLogURL, atomically: false, encoding: .utf8)
        } catch {
            await BacktraceLogger.warning("Error clearing breadcrumb log file at: \(breadcrumbLogURL) - \(error.localizedDescription)")
        }
    }
}
