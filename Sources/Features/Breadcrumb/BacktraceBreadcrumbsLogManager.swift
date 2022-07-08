import Foundation

@objc class BacktraceBreadcrumbsLogManager: NSObject {
    
    private var breadcrumbId = Date().millisecondsSince1970
    
    private var backtraceBreadcrumbFileHelper: BacktraceBreadcrumbFileHelper?

    init(_ breadcrumbLogPath: String, maxQueueFileSizeBytes: Int) {
        super.init()
        self.backtraceBreadcrumbFileHelper = BacktraceBreadcrumbFileHelper(breadcrumbLogPath, maxQueueFileSizeBytes: maxQueueFileSizeBytes)
    }
    
    func addBreadcrumb(_ message: String,
                       attributes:[String:Any]? = nil,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel) -> Bool {
        let time = Date().millisecondsSince1970
        var breadcrumb: [String: Any] = ["timestamp": time,
                                         "id": breadcrumbId,
                                         "level": level.info,
                                         "type": type.info,
                                         "message": message]
        if let attributes = attributes, !attributes.keys.isEmpty {
            var attribInfo: [String: Any] = [String: Any]()
            for attribute in attributes {
                attribInfo[attribute.key] = attribute.value
            }
            breadcrumb["attributes"] = attribInfo
        }
        breadcrumbId += 1
        if let result = backtraceBreadcrumbFileHelper?.addBreadcrumb(breadcrumb), result == true {
            return result
        }
        return false
    }
    
    func clear() -> Bool {
        let result = backtraceBreadcrumbFileHelper?.clear()
        if result == true {
            breadcrumbId = 0;
        }
        return result ?? false
    }
    
    var getCurrentBreadcrumbId: Int {
        breadcrumbId
    }
}
	
