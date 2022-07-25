import Foundation

/// Backtrace error-free breadcrumb settings
@objc public class BacktraceBreadcrumbSettings: NSObject {

    /// Max byte size of breadcrumb
    @objc public var maxBreadcrumbSizeBytes: Int = 4096

    /// Max byte size of breadcrumb
    @objc public var maxQueueFileSizeBytes: Int = 64000

    /// File name to write breadcrumb
    @objc public var breadcrumbLogFileName = "bt-breadcrumbs-0"

    var breadcrumbTypes: [BacktraceBreadcrumbType] = BacktraceBreadcrumbType.all

    @objc
    public init(_ maxBreadcrumbSizeBytes: Int = 4096,
                maxQueueFileSizeBytes: Int = 64000,
                breadcrumbLogFileName: String = "bt-breadcrumbs-0",
                breadcrumbTypes: [Int]) {
        self.maxBreadcrumbSizeBytes = maxBreadcrumbSizeBytes
        self.maxQueueFileSizeBytes = maxQueueFileSizeBytes
        self.breadcrumbLogFileName = breadcrumbLogFileName
        self.breadcrumbTypes = breadcrumbTypes.compactMap({ BacktraceBreadcrumbType(rawValue: $0) })
        super.init()
    }

    public init(_ maxBreadcrumbSizeBytes: Int = 4096,
                maxQueueFileSizeBytes: Int = 64000,
                breadcrumbLogFileName: String = "bt-breadcrumbs-0",
                breadcrumbTypes: [BacktraceBreadcrumbType] = BacktraceBreadcrumbType.all) {
        super.init()
        self.maxBreadcrumbSizeBytes = maxBreadcrumbSizeBytes
        self.maxQueueFileSizeBytes = maxQueueFileSizeBytes
        self.breadcrumbLogFileName = breadcrumbLogFileName
        self.breadcrumbTypes = breadcrumbTypes
    }

    @objc public func getBreadcrumbLogPath() throws -> URL {
        var fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        fileURL.appendPathComponent(breadcrumbLogFileName)
        return fileURL
    }
}
