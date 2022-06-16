import Foundation

@objc public class BacktraceBreadcrumbsLogManager: NSObject {
    
    private var breadcrumbId = Date().timeIntervalSince1970
    
    private var backtraceQueueFileHelper: BacktraceQueueFileHelper?

    public init(_ breadcrumbLogPath: String, maxQueueFileSizeBytes: Int) {
        super.init()
        self.backtraceQueueFileHelper = BacktraceQueueFileHelper(breadcrumbLogPath, maxQueueFileSizeBytes: maxQueueFileSizeBytes)
    }
    
    public func addBreadcrumb(_ message: String,
                              attributes:[String:Any]? = nil,
                              type: BacktraceBreadcrumbType,
                              level: BacktraceBreadcrumbLevel) -> Bool {
        let time = Date().timeIntervalSince1970
        
        var info: [String: Any] = ["timestamp": time,
                    "id": breadcrumbId,
                    "level": level.info,
                    "type": type.info,
                    "message": message]
        if let attributes = attributes {
            for attribute in attributes {
                info[attribute.key] = attribute.value
            }
        }
        
        if let result = backtraceQueueFileHelper?.addInfo(info), result == true {
            breadcrumbId += 1
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
}
	
