import Foundation

@objc class BacktraceBreadcrumbsLogManager: NSObject {

    private var breadcrumbId: Int
    private let backtraceBreadcrumbFileHelper: BacktraceBreadcrumbFileHelper

    init(breadcrumbSettings: BacktraceBreadcrumbSettings) throws {
        self.backtraceBreadcrumbFileHelper = try BacktraceBreadcrumbFileHelper(breadcrumbSettings)
        if let lastBreadcrumbId = backtraceBreadcrumbFileHelper.getCurrentBreadcrumbId {
            BreadcrumbsInfo.currentBreadcrumbsId = lastBreadcrumbId
            breadcrumbId = lastBreadcrumbId + 1
        } else {
            breadcrumbId = Date().millisecondsSince1970 + 1
        }
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
        BreadcrumbsInfo.currentBreadcrumbsId = breadcrumbId
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
}
