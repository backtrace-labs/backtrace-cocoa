import Foundation
import Cassette

enum BacktraceBreadcrumbFileHelperError: Error {
    case invalidFormat
}

@objc class BacktraceBreadcrumbFileHelper: NSObject {

    /*
     The underlying library CASQueueFile assigns a minimum of 4k (filled with zeroes).
     Since we know that space will be allocated (and uploaded) anyways, set it as the minimum.
     */
    private static let minimumQueueFileSizeBytes = 4096

    /* We cap the size of an individual breadcrumb at 4k, for performance reasons. */
    private static let maximumBreadcrumbSize = 4096

    private let maxQueueFileSizeBytes: Int
    public let breadcrumbFile: String

    private let queue: CASQueueFile

    public init(_ breadcrumbFile: String, maxQueueFileSizeBytes: Int) throws {
        do {
            self.queue = try CASQueueFile.init(path: breadcrumbFile)
        } catch {
            BacktraceLogger.error("\(error.localizedDescription) \nWhen enabling breadcrumbs")
            throw error
        }
        self.breadcrumbFile =  breadcrumbFile

        if maxQueueFileSizeBytes < BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes {
            BacktraceLogger.warning("\(maxQueueFileSizeBytes) is smaller than the minimum of " +
                                    "\(BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes)" +
                                    ", ignoring value and overriding with minimum.")
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
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen converting breadcrumb to string")
            return false
        }

        let textBytes = Data(text.utf8)
        if textBytes.count > BacktraceBreadcrumbFileHelper.maximumBreadcrumbSize {
            BacktraceLogger.warning("We should not have a breadcrumb this big, this is a bug! Discarding breadcrumb.")
            return false
        }

        do {
            // Keep removing until there's enough space to add the new breadcrumb
            while (queueByteSize() + textBytes.count) > maxQueueFileSizeBytes {
                try queue.pop(1, error: ())
            }

            try queue.add(textBytes, error: ())
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen adding breadcrumb to file")
            return false
        }

        return true
    }

    func clear() -> Bool {
        do {
            try queue.clearAndReturnError()
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen clearing breadcrumb file")
            return false
        }
        return true
    }
    
    internal var getCurrentBreadcrumbId: Int? {
        do {
            if let breadcrumbData = try queue.peek(queue.size(), error: (
            )).last, let
                breadcrumbText = String(data: breadcrumbData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                let data = breadcrumbText.data(using: .utf8),
               let breadcrumbDic = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let breadcrumbId = breadcrumbDic["id"] as? Int {
                return breadcrumbId
            }
        } catch  {
        }
        return nil
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
