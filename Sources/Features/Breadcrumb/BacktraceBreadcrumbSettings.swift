import Foundation

/// Backtrace error-free breadcrumb settings
@objc public class BacktraceBreadcrumbSettings: NSObject {
    public static let defaultMaxBreadcrumbFileSize = 64 * 1024

    /// Max byte size of breadcrumb
    @objc public var maxIndividualBreadcrumbSizeBytes: Int

    /// Max byte size of breadcrumbs file. Note this has to be a power of 2 (4k, 8k, 16k, 32k, 64k)
    @objc public var maxQueueFileSizeBytes: Int

    /// File name to write breadcrumb
    @objc public let breadcrumbLogFileName: String

    /// Breadcrumb types allow to add
    var breadcrumbTypes: [BacktraceBreadcrumbType] = BacktraceBreadcrumbType.all

    /// Breadcrumb level allow to add
    @objc public var breadcrumbLevel: BacktraceBreadcrumbLevel = BacktraceBreadcrumbLevel.debug

    @objc
    public init(_ maxIndividualBreadcrumbSizeBytes: Int = 4096,
                maxQueueFileSizeBytes: Int = defaultMaxBreadcrumbFileSize,
                breadcrumbLogFileName: String = "bt-breadcrumbs-0",
                breadcrumbTypes: [Int],
                breadcrumbLevel: Int) {
        self.maxIndividualBreadcrumbSizeBytes = maxIndividualBreadcrumbSizeBytes
        self.maxQueueFileSizeBytes = maxQueueFileSizeBytes
        self.breadcrumbLogFileName = breadcrumbLogFileName
        self.breadcrumbTypes = breadcrumbTypes.compactMap({ BacktraceBreadcrumbType(rawValue: $0) })
        self.breadcrumbLevel = BacktraceBreadcrumbLevel(rawValue: breadcrumbLevel) ?? .debug
        super.init()
    }

    public init(_ maxIndividualBreadcrumbSizeBytes: Int = 4096,
                maxQueueFileSizeBytes: Int = defaultMaxBreadcrumbFileSize,
                breadcrumbLogFileName: String = "bt-breadcrumbs-0",
                breadcrumbTypes: [BacktraceBreadcrumbType] = BacktraceBreadcrumbType.all,
                breadcrumbLevel: BacktraceBreadcrumbLevel = BacktraceBreadcrumbLevel.debug) {
        self.maxIndividualBreadcrumbSizeBytes = maxIndividualBreadcrumbSizeBytes
        self.maxQueueFileSizeBytes = maxQueueFileSizeBytes
        self.breadcrumbLogFileName = breadcrumbLogFileName
        self.breadcrumbTypes = breadcrumbTypes
        self.breadcrumbLevel = breadcrumbLevel
        super.init()
    }

    @objc public func getBreadcrumbLogPath() throws -> URL {
        var fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        fileURL.appendPathComponent(breadcrumbLogFileName)
        return fileURL
    }
}
