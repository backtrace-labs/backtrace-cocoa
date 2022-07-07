import Foundation

@objc public class BacktraceBreadcrumbsLogManager: NSObject {
    
    private var breadcrumbId = Date().millisecondsSince1970
    
    private var backtraceQueueFileHelper: BacktraceQueueFileHelper?

    public init(_ breadcrumbLogPath: String, maxQueueFileSizeBytes: Int) {
        super.init()
        self.backtraceQueueFileHelper = BacktraceQueueFileHelper(breadcrumbLogPath, maxQueueFileSizeBytes: maxQueueFileSizeBytes)
    }
    
    public func addBreadcrumb(_ message: String,
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
        if let result = backtraceQueueFileHelper?.addBreadcrumb(breadcrumb), result == true {
            return result
        }
        return false
    }
    
    public func clear() -> Bool {
        let result = backtraceQueueFileHelper?.clear()
        if result == true {
            breadcrumbId = 0;
        }
        return result ?? false
    }
    
    public var getCurrentBreadcrumbId: Int {
        breadcrumbId
    }
}
	
