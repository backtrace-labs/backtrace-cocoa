import Foundation

@objc class BacktraceBreadcrumbsLogManager: NSObject {

    public let breadcrumbLogPath: String

    private static let breadcrumbLogFileName = "bt-breadcrumbs-0"

    private lazy var breadcrumbId: Int = {
        return (backtraceBreadcrumbFileHelper.getCurrentBreadcrumbId ?? Date().millisecondsSince1970) + 1
    }()
    private let backtraceBreadcrumbFileHelper: BacktraceBreadcrumbFileHelper

    init(maxQueueFileSizeBytes: Int) throws {
        self.breadcrumbLogPath = try BacktraceBreadcrumbsLogManager.getBreadcrumbLogPath()
        self.backtraceBreadcrumbFileHelper = try BacktraceBreadcrumbFileHelper(self.breadcrumbLogPath,
                                                                               maxQueueFileSizeBytes: maxQueueFileSizeBytes)
        super.init()
    }

    func addBreadcrumb(_ message: String,
                       attributes: [String: String]? = nil,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel) -> Bool {
        let time = Date().millisecondsSince1970
        var breadcrumb: [String: Any] = ["timestamp": time,
                                         "id": breadcrumbId,
                                         "level": level.description,
                                         "type": type.description,
                                         "message": message]
        breadcrumb["attributes"] = attributes
        breadcrumbId += 1
        return backtraceBreadcrumbFileHelper.addBreadcrumb(breadcrumb)
    }

    func clear() -> Bool {
        let result = backtraceBreadcrumbFileHelper.clear()
        if result {
            breadcrumbId = Date().millisecondsSince1970
        }
        return result
    }

    internal var getCurrentBreadcrumbId: Int? {
        return backtraceBreadcrumbFileHelper.getCurrentBreadcrumbId ?? breadcrumbId
    }

    private static func getBreadcrumbLogPath() throws -> String {
        var fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        fileURL.appendPathComponent(BacktraceBreadcrumbsLogManager.breadcrumbLogFileName)
        return fileURL.path
    }
}
