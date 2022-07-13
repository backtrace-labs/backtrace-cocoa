import Foundation

@objc class BacktraceBreadcrumbsLogManager: NSObject {

    private var breadcrumbId = Date().millisecondsSince1970
    private let backtraceBreadcrumbFileHelper: BacktraceBreadcrumbFileHelper

    init(_ breadcrumbLogPath: String, maxQueueFileSizeBytes: Int) throws {
        self.backtraceBreadcrumbFileHelper = try BacktraceBreadcrumbFileHelper(breadcrumbLogPath,
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
                                         "level": level.info,
                                         "type": type.info,
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

    var getCurrentBreadcrumbId: Int {
        breadcrumbId
    }
}
