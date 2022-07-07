import Foundation
import Cassette

enum BacktraceQueueFileError: Error {
    case invalidFormat
}

@objc public class BacktraceQueueFileHelper: NSObject {
    
    private var minimumQueueFileSizeBytes = 4096;
    private var maxQueueFileSizeBytes = 0
    private var breadcrumbLogDirectory: String = ""
        
    private var queue: QueueFile?
    
    private lazy var queueByteSize: Int = {
        var size = 0
        queue?.forEach({ data in
            size += data?.count ?? 0
            return true
        })
       return size
    }()
    
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
            if queueByteSize + textBytes.count > maxQueueFileSizeBytes {
                queue?.clear()
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


extension BacktraceQueueFileHelper {
    
    func convertBreadcrumbIntoString(_ breadcrumb: Any) throws -> String {
        let breadcrumbData = try JSONSerialization.data( withJSONObject: breadcrumb, options: [])
        if let breadcrumbText = String(data: breadcrumbData, encoding: .ascii) {
            return breadcrumbText
        }
        throw BacktraceQueueFileError.invalidFormat
    }
}
