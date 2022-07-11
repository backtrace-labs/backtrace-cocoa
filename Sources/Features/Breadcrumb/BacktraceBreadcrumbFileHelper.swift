import Foundation
import Cassette

enum BacktraceBreadcrumbFileHelperError: Error {
    case invalidFormat
}

@objc public class BacktraceBreadcrumbFileHelper: NSObject {

    private static let minimumQueueFileSizeBytes = 4096
    private var maxQueueFileSizeBytes = 0
    private var breadcrumbLogDirectory: String

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

    private func queueByteSize() -> Int {
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

    func addBreadcrumb(_ breadcrumb: [String: Any]) -> Bool {
        do {
            let text = try convertBreadcrumbIntoString(breadcrumb)

            let textBytes = Data(text.utf8)
            if textBytes.count > 4096 {
                BacktraceLogger.error("We should not have a breadcrumb this big, this is a bug!")
                return false
            }
            while (queueByteSize() + textBytes.count) > maxQueueFileSizeBytes {
                queue.pop(1)
            }
            queue.add(textBytes)
            return true
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen adding breadcrumb")
            return false
        }
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
}

extension CASQueueFile {
//    /**
//     * Initial file size in bytes.
//     */
//    static NSUInteger const QueueFileInitialLength = 4096;
//
//    /**
//     * Length of header in bytes.
//     */
//    static NSUInteger const QueueFileHeaderLength = 16;
//
//    /**
//     * Length of element header in bytes.
//     */
//    static NSUInteger const ElementHeaderLength = 4;

//    func usedBytes() -> Int {
//
//        let mirror = Mirror(reflecting: self)
//        mirror.
//    }
}
