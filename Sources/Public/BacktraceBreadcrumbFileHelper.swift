import Foundation
import Cassette

enum BacktraceBreadcrumbFileHelperError: Error {
    case invalidFormat
}

@objc public class BacktraceBreadcrumbFileHelper: NSObject {
    
    private var minimumQueueFileSizeBytes = 4096;
    private var maxQueueFileSizeBytes = 0
    private var breadcrumbLogDirectory: String = ""
        
    private var queue: QueueFile?
    
    private var queueByteSize: Int {
        var size = 0
        queue?.forEach({ data in
            size += data?.count ?? 0
            return true
        })
       return size
    }
    
    public init(_ breadcrumbLogDirectory: String, maxQueueFileSizeBytes: Int) {
        super.init()
        print(breadcrumbLogDirectory)
        self.queue = QueueFile.init(path: breadcrumbLogDirectory)
        self.breadcrumbLogDirectory =  breadcrumbLogDirectory
        if (maxQueueFileSizeBytes < minimumQueueFileSizeBytes) {
            self.maxQueueFileSizeBytes = minimumQueueFileSizeBytes;
        } else {
            self.maxQueueFileSizeBytes = maxQueueFileSizeBytes;
        }
    }
     
    func addBreadcrumb(_ breadcrumb:[String:Any]) -> Bool {
        do {
            var text = try convertBreadcrumbIntoString(breadcrumb)
            if queue?.isEmpty() == false {
                text = "\n\n\(text)"
            }
            let textBytes = Data(text.utf8)
            if textBytes.count > 4096 {
                BacktraceLogger.error("We should not have a breadcrumb this big, this is a bug!")
                return false
            }
            while queueByteSize + textBytes.count > maxQueueFileSizeBytes {
                queue?.remove()
            }
            queue?.add(textBytes)
            return true
        } catch  {
            return false
        }
    }
    
    func clear() -> Bool {
        queue?.clear()
        return true
    }
}


extension BacktraceBreadcrumbFileHelper {
    
    func convertBreadcrumbIntoString(_ breadcrumb: Any) throws -> String {
        let breadcrumbData = try JSONSerialization.data( withJSONObject: breadcrumb, options: [])
        if let breadcrumbText = String(data: breadcrumbData, encoding: .utf8) {
            return breadcrumbText
        }
        throw BacktraceBreadcrumbFileHelperError.invalidFormat
    }
}
