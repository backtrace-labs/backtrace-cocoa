import Foundation

@objc class BacktraceBreadcrumbsLogManager: NSObject {

    private var breadcrumbId: Int
    private let backtraceBreadcrumbFile: BacktraceBreadcrumbFile
    private let lock = NSLock()

    init(breadcrumbSettings: BacktraceBreadcrumbSettings) throws {
        self.backtraceBreadcrumbFile = try BacktraceBreadcrumbFile(breadcrumbSettings)

        self.breadcrumbId = Date().millisecondsSince1970
        BreadcrumbsInfo.currentBreadcrumbsId = breadcrumbId

        super.init()
    }

    func addBreadcrumb(_ message: String,
                       attributes: [String: String]? = nil,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel) -> Bool {
        let currentId = lock.withLock { () -> Int in
            breadcrumbId += 1
            BreadcrumbsInfo.currentBreadcrumbsId = breadcrumbId
            return breadcrumbId
        }

        let time = Date().millisecondsSince1970
        var breadcrumb: [String: Any] = ["timestamp": time,
                                         "id": currentId,
                                         "level": level.description,
                                         "type": type.description,
                                         "message": message]
        breadcrumb["attributes"] = attributes

        return backtraceBreadcrumbFile.addBreadcrumb(breadcrumb)
    }

    func clear() -> Bool {
        let result = backtraceBreadcrumbFile.clear()
        if result {
            lock.withLock {
                breadcrumbId = Date().millisecondsSince1970
                BreadcrumbsInfo.currentBreadcrumbsId = breadcrumbId
            }
        }
        return result
    }

    internal var getCurrentBreadcrumbId: Int? {
        return lock.withLock { breadcrumbId }
    }
}

extension BacktraceBreadcrumbsLogManager: @unchecked Sendable {}
