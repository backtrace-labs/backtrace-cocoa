import Foundation

enum BacktraceBreadcrumbFileError: Error {
    case invalidFormat
}

@objc class BacktraceBreadcrumbFile: NSObject {

    private static let minimumQueueFileSizeBytes = 4096
    private let maximumIndividualBreadcrumbSize: Int
    private let maxQueueFileSizeBytes: Int
    private let queue: Queue<BreadcrumbRecord>
    private let breadcrumbLogURL: URL
    private let dispatchQueue = DispatchQueue(label: "io.backtrace.BacktraceBreadcrumbFile@\(UUID().uuidString)")

    public init(_ breadcrumbSettings: BacktraceBreadcrumbSettings) throws {
        self.breadcrumbLogURL = try breadcrumbSettings.getBreadcrumbLogPath()
        self.queue = Queue<BreadcrumbRecord>()
        self.maximumIndividualBreadcrumbSize = breadcrumbSettings.maxIndividualBreadcrumbSizeBytes
        if breadcrumbSettings.maxQueueFileSizeBytes < BacktraceBreadcrumbFile.minimumQueueFileSizeBytes {
            BacktraceLogger.warning("\(breadcrumbSettings.maxQueueFileSizeBytes) is smaller than the minimum of " +
                                    "\(BacktraceBreadcrumbFile.minimumQueueFileSizeBytes)" +
                                    ", ignoring value and overriding with minimum.")
            self.maxQueueFileSizeBytes = BacktraceBreadcrumbFile.minimumQueueFileSizeBytes
        } else {
            self.maxQueueFileSizeBytes = breadcrumbSettings.maxQueueFileSizeBytes
        }

        super.init()
    }

    func addBreadcrumb(_ breadcrumb: [String: Any]) -> Bool {
        do {
            let breadcrumbJsonData = try JSONSerialization.data(withJSONObject: breadcrumb)
            guard let breadcrumbJsonString = String(data: breadcrumbJsonData, encoding: .utf8) else {
                BacktraceLogger.warning("Error when converting breadcrumb to string")
                return false
            }
            let breadcrumbSize = breadcrumbJsonData.count
            // Check if breadcrumb size is larger than the maximum specified
            if breadcrumbSize > maximumIndividualBreadcrumbSize {
                BacktraceLogger.warning(
                    "Discarding breadcrumb that was larger than the maximum specified (\(maximumIndividualBreadcrumbSize).")
                return false
            }
            let queueBreadcrumb = BreadcrumbRecord(size: breadcrumbSize, json: breadcrumbJsonString)
            queue.enqueue(queueBreadcrumb)
            _ = dispatchQueue.sync {
                let queuedBreadcrumbs = queue.allElements()
                var breadcrumbsArray = [String]()
                var size = 0
                for index in (0..<queue.count).reversed() {
                    let queueBreadcrumb = queuedBreadcrumbs[index]
                    let breadcrumbSize = queueBreadcrumb.size
                    // Pop last element if size is greater than maxQueueFileSizeBytes
                    if size + breadcrumbSize > maxQueueFileSizeBytes && !queue.isEmpty {
                        while (index != 0) {
                            _ = queue.pop(at: index)
                        }
                        break
                    } else {
                        let breadcrumbJsonData = queueBreadcrumb.json
                        breadcrumbsArray.append(breadcrumbJsonData)
                        size += breadcrumbSize
                    }
                }
                let breadcrumbString = "[\(breadcrumbsArray.joined(separator: ","))]"
                writeBreadcrumbToLogFile(breadcrumb: breadcrumbString, at: self.breadcrumbLogURL)
                return true
            }
        } catch {
            BacktraceLogger.warning("Error when adding breadcrumb to file: \(error)")
            return false
        }
        return true
    }

    func clear() -> Bool {
        dispatchQueue.sync {
            queue.clear()
            clearBreadcrumbLogFile(at:self.breadcrumbLogURL)
        }
        return true
    }
}

extension BacktraceBreadcrumbFile {
    
    func writeBreadcrumbToLogFile(breadcrumb: String, at breadcrumbLogURL: URL) {
        do {
            try breadcrumb.write(to: breadcrumbLogURL, atomically: true, encoding: .utf8)
        } catch {
            BacktraceLogger.warning("Error writing breadcrumb to log file at: \(breadcrumbLogURL) - \(error.localizedDescription)")
        }
    }

    func clearBreadcrumbLogFile(at breadcrumbLogURL: URL) {
        do {
            try "".write(to: breadcrumbLogURL, atomically: false, encoding: .utf8)
        } catch {
            BacktraceLogger.warning("Error clearing breadcrumb log file at: \(breadcrumbLogURL) - \(error.localizedDescription)")
        }
    }
}
