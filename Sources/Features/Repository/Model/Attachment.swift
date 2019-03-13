import Foundation
#if os(iOS)
import MobileCoreServices
#endif

struct Attachment {
    let data: Data
    let name: String
    let mimeType: String
    
    init?(filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        mimeType = Attachment.mimeTypeForPath(path: filePath)
        name = "attachment_" + (fileURL.lastPathComponent as NSString).deletingPathExtension + "_\(arc4random())"
        
        guard let fileData = try? Data(contentsOf: fileURL,
                                       options: Data.ReadingOptions.mappedIfSafe)
        else { return nil }
        data = fileData
    }
    
    static func mimeTypeForPath(path: String) -> String {
        let url = NSURL(fileURLWithPath: path)
        guard let pathExtension = url.pathExtension else { return "application/octet-stream" }
        
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                           pathExtension as NSString,
                                                           nil)?.takeRetainedValue() {
            
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }
}
