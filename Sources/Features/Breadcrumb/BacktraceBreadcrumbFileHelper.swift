import Foundation
import Cassette

enum BacktraceBreadcrumbFileHelperError: Error {
    case invalidFormat
}

@objc public class BacktraceBreadcrumbFileHelper: NSObject {

    /*
     The underlying library CASQueueFile assigns a minimum of 4k (filled with zeroes).
     Since we know that space will be allocated (and uploaded) anyways, set it as the minimum.
     */
    private static let minimumQueueFileSizeBytes = 4096
    
    private let maxQueueFileSizeBytes: Int
    private let breadcrumbLogDirectory: String

    private let queue: CASQueueFile

    public init(_ breadcrumbLogDirectory: String, maxQueueFileSizeBytes: Int) throws {
        do {
            self.queue = try CASQueueFile.init(path: breadcrumbLogDirectory)
        } catch {
            BacktraceLogger.error("\(error.localizedDescription) \nWhen enabling breadcrumbs")
            throw error
        }
        self.breadcrumbLogDirectory =  breadcrumbLogDirectory

        if maxQueueFileSizeBytes < BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes {
            BacktraceLogger.warning("\(maxQueueFileSizeBytes) is smaller than the minimum of \(BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes), ignoring value.")
            self.maxQueueFileSizeBytes = BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes
        } else {
            self.maxQueueFileSizeBytes = maxQueueFileSizeBytes
        }

        super.init()
    }

    func addBreadcrumb(_ breadcrumb: [String: Any]) -> Bool {
        let text: String
        do {
            text = try convertBreadcrumbIntoString(breadcrumb)
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen adding breadcrumb")
            return false
        }

        let textBytes = Data(text.utf8)
        if textBytes.count > 4096 {
            BacktraceLogger.warning("We should not have a breadcrumb this big, this is a bug! Discarding breadcrumb.")
            return false
        }

        // Keep removing until there's enough space to add the new breadcrumb
        while (queueByteSize() + textBytes.count) > maxQueueFileSizeBytes {
            queue.pop(1)
        }

        queue.add(textBytes)
        return true
    }

    func clear() -> Bool {
        queue.clear()
        return true
    }
}

extension BacktraceBreadcrumbFileHelper {

    func convertBreadcrumbIntoString(_ breadcrumb: Any) throws -> String {
        let breadcrumbData = try JSONSerialization.data( withJSONObject: breadcrumb, options: [])
        if let breadcrumbText = String(data: breadcrumbData, encoding: .utf8) {
            return "\n\(breadcrumbText)\n"
        }
        throw BacktraceBreadcrumbFileHelperError.invalidFormat
    }

    func queueByteSize() -> Int {
        // This is the current fileLength of the QueueFile
        guard let fileLength = queue.value(forKey: "fileLength") as? Int else {
            BacktraceLogger.error("fileLength is not an Int, this is unexpected!")
            return maxQueueFileSizeBytes
        }

        // let usedBytes = queue.value(forKey: "usedBytes") as? Int

        // This is the remaining bytes before the file needs to be expanded
        guard let remainingBytes = queue.value(forKey: "remainingBytes") as? Int else {
            BacktraceLogger.error("remainingBytes is not an Int, this is unexpected!")
            return 0
        }

        return fileLength - remainingBytes
    }
}
