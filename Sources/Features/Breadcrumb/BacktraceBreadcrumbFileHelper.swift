import Foundation

enum BacktraceBreadcrumbFileHelperError: Error {
    case invalidFormat
}

@objc class BacktraceBreadcrumbFileHelper: NSObject {

    /*
     The underlying library CASQueueFile assigns a minimum of 4k (filled with zeroes).
     Since we know that space will be allocated (and uploaded) anyways, set it as the minimum.
     */
    private static let minimumQueueFileSizeBytes = 4096

    private let maximumIndividualBreadcrumbSize: Int
    private let maxQueueFileSizeBytes: Int

    /** CASQueueFile is not thread safe, so all interactions with it should be done synchronously through this DispathQueue */
    private let dispatchQueue = DispatchQueue(label: "io.backtrace.BacktraceBreadcrumbFileHelper@\(UUID().uuidString)")

    public init(_ breadcrumbSettings: BacktraceBreadcrumbSettings) throws {

        self.maximumIndividualBreadcrumbSize = breadcrumbSettings.maxIndividualBreadcrumbSizeBytes

        if breadcrumbSettings.maxQueueFileSizeBytes < BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes {
            BacktraceLogger.warning("\(breadcrumbSettings.maxQueueFileSizeBytes) is smaller than the minimum of " +
                                    "\(BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes)" +
                                    ", ignoring value and overriding with minimum.")
            self.maxQueueFileSizeBytes = BacktraceBreadcrumbFileHelper.minimumQueueFileSizeBytes
        } else {
            self.maxQueueFileSizeBytes = breadcrumbSettings.maxQueueFileSizeBytes
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
        if textBytes.count > maximumIndividualBreadcrumbSize {
            BacktraceLogger.warning(
                "Discarding breadcrumb that was larger than the maximum specified (\(maximumIndividualBreadcrumbSize).")
            return false
        }

        return true
    }

    func clear() -> Bool {
        
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

        return 0
    }
}
