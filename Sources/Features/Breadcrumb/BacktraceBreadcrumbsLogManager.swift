import Foundation

@objc class BacktraceBreadcrumbsLogManager: NSObject {

    private var breadcrumbId: Int
    private let backtraceBreadcrumbFile: BacktraceBreadcrumbFile

    init(breadcrumbSettings: BacktraceBreadcrumbSettings) throws {
        self.backtraceBreadcrumbFile = try BacktraceBreadcrumbFile(breadcrumbSettings)

        self.breadcrumbId = Date().millisecondsSince1970
        BreadcrumbsInfo.currentBreadcrumbsId = breadcrumbId

        super.init()
    }

    func addBreadcrumb(_ message: String,
                       attributes: [String: String]? = nil,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel) async -> Bool {
        breadcrumbId += 1
        BreadcrumbsInfo.currentBreadcrumbsId = breadcrumbId

        let time = Date().millisecondsSince1970
        var breadcrumb: [String: Any] = ["timestamp": time,
                                         "id": breadcrumbId,
                                         "level": level.description,
                                         "type": type.description,
                                         "message": message]
        breadcrumb["attributes"] = attributes

        return await backtraceBreadcrumbFile.addBreadcrumb(breadcrumb)
    }

    func clear() async -> Bool {
        let result = await backtraceBreadcrumbFile.clear()
        if result {
            breadcrumbId = Date().millisecondsSince1970
            BreadcrumbsInfo.currentBreadcrumbsId = breadcrumbId
        }
        return result
    }

    internal var getCurrentBreadcrumbId: Int? {
        return breadcrumbId
    }
}
