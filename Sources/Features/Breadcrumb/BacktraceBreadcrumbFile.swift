import Foundation

enum BacktraceBreadcrumbFileError: Error {
    case invalidFormat
}

@objc class BacktraceBreadcrumbFile: NSObject {

    private static let minimumQueueFileSizeBytes = 4096

    private let maximumIndividualBreadcrumbSize: Int
    private let maxQueueFileSizeBytes: Int
    
    private let queue: Queue<Any>
    private let breadcrumbLogURL: URL

    private let dispatchQueue = DispatchQueue(label: "io.backtrace.BacktraceBreadcrumbFile@\(UUID().uuidString)")

    public init(_ breadcrumbSettings: BacktraceBreadcrumbSettings) throws {
        
        self.breadcrumbLogURL = try breadcrumbSettings.getBreadcrumbLogPath()
        self.queue = Queue<Any>()
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
            // Serialize breadcrumb: [String: Any] into Data
            let breadcrumbJsonData = try JSONSerialization.data(withJSONObject: breadcrumb)
            // Serialize Data into a JSON string
            guard let breadcrumbJsonString = String(data: breadcrumbJsonData, encoding: .utf8) else {
                BacktraceLogger.warning("Error when adding breadcrumb to file")
                return false
            }
            // Calculate the size of the breadcrumb and add it to queue
            let breadcrumbSize = breadcrumbJsonData.count
            // Check if breadcrumb size is larger than the maximum specified
            if breadcrumbSize > maximumIndividualBreadcrumbSize {
                BacktraceLogger.warning(
                    "Discarding breadcrumb that was larger than the maximum specified (\(maximumIndividualBreadcrumbSize).")
                return false
            }
            // Store breadcrumb Json String and size in Dictionary [String : Any]
            let queueBreadcrumb = ["breadcrumbJson": breadcrumbJsonString, "size": breadcrumbSize] as [String : Any]
            // Queue breacrumb
            queue.enqueue(queueBreadcrumb)
            // Iterate over the queue from newest to oldest breadcrumb and build an array of encoded strings
            let queuedBreadcrumbs = queue.allElements()
            var breadcrumbsArray = [String]()
            var size = 0
            for index in (0..<queue.count).reversed() {
                guard let queueBreadcrumb = queuedBreadcrumbs[index] as? [String: Any] else {
                    BacktraceLogger.warning("Error weh fetching breacrumbs from queue")
                    return false
                }
                guard let breadcrumbSize = queueBreadcrumb["size"] as? Int else {
                    BacktraceLogger.warning("Error when adding breadcrumbSize to array")
                    return false
                }
                // Pop last element if size is greater than maxQueueFileSizeBytes
                if size + breadcrumbSize > maxQueueFileSizeBytes && !queue.isEmpty {
                    queue.pop()
                } else {
                    guard let breadcrumbJsonData = queueBreadcrumb["breadcrumbJson"] as? String else {
                        BacktraceLogger.warning("Error when adding breadcrumbJson to array")
                        return false
                    }
                    breadcrumbsArray.append(breadcrumbJsonData)
                    size += breadcrumbSize
                }
            }
            // Write breadcrumbs to file
            let breadcrumbString = "[\(breadcrumbsArray.joined(separator: ","))]"
            try breadcrumbString.write(to: self.breadcrumbLogURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            BacktraceLogger.warning("Error when adding breadcrumb to file: \(error)")
            return false
        }
    }

    func clear() -> Bool {
        dispatchQueue.sync {
            queue.clear()
            clearBreadcrumbLogFile(at:self.breadcrumbLogURL)
        }
        return true
    }
    
    func clearBreadcrumbLogFile(at breadcrumbLogURL: URL) {
        do {
            try "".write(to: breadcrumbLogURL, atomically: false, encoding: .utf8)
        } catch {
            BacktraceLogger.warning("Error clearing breadcrumb log file at: \(breadcrumbLogURL) - \(error.localizedDescription)")
        }
    }
}
