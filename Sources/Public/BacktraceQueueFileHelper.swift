import Foundation

@objc public class BacktraceQueueFileHelper: NSObject {
    
    private var minimumQueueFileSizeBytes = 4096;
    private var maxQueueFileSizeBytes = 0
    private var breadcrumbLogDirectory: String = ""
        
    public init(_ breadcrumbLogDirectory: String, maxQueueFileSizeBytes: Int) {
        super.init()
        self.breadcrumbLogDirectory =  breadcrumbLogDirectory
        if (maxQueueFileSizeBytes < minimumQueueFileSizeBytes) {
            self.maxQueueFileSizeBytes = minimumQueueFileSizeBytes;
        } else {
            self.maxQueueFileSizeBytes = maxQueueFileSizeBytes;
        }
    }
     
    func addInfo(_ info:[String:Any]) -> Bool {
    
        if let text = convertInfoIntoString(info) {
            let textBytes = Data(text.utf8)
            if textBytes.count > 4096 {
                BacktraceLogger.error("We should not have a breadcrumb this big, this is a bug!")
                return false
            }
            
            let fileURL = URL(fileURLWithPath: breadcrumbLogDirectory)
            let content = try? String(contentsOf: fileURL, encoding: .utf8)
            do {
                var fullContent = ""
                if let content = content {
                    fullContent = content
                }
                let contentBytes = Data(fullContent.utf8)
                if contentBytes.count + textBytes.count > maxQueueFileSizeBytes {
                    fullContent = ""
                }
                if fullContent.isEmpty {
                    fullContent = text
                } else {
                    fullContent.append("\n\n\(text)")
                }
                try fullContent.write(to: fileURL, atomically: true, encoding: .utf8)
                return true
            }
            catch {
                BacktraceLogger.warning("\(error.localizedDescription) \nWhen adding breadcrumbs")
                return false
            }
        }
        return false
    }
    
    func clear() -> Bool {
        do {
            let fileURL = URL(fileURLWithPath: breadcrumbLogDirectory)
            try "".write(to: fileURL, atomically: false, encoding: .utf8)
            return true
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen clearing breadcrumbs")
            return false
        }
    }
}


extension BacktraceQueueFileHelper {
    
    func getSavedContent() -> [[String:Any]]? {
        do {
            let fileURL = URL(fileURLWithPath: breadcrumbLogDirectory)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return convertStringIntoInfo(content)
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen try to read breadcrumbs log file")
            return nil
        }
    }
    
    func convertStringIntoInfo(_ text: String) -> [[String:Any]]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
            } catch {
                BacktraceLogger.warning("\(error.localizedDescription) \nWhen try to convert text into json object")
                return nil
            }
        }
        return nil
    }
    
    func convertInfoIntoString(_ info: Any) -> String? {
        do {
            let theJSONData = try JSONSerialization.data( withJSONObject: info, options: [])
            let text = String(data: theJSONData, encoding: .ascii)
            return text
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen try to convert json object into text")
            return nil
        }
    }
}
