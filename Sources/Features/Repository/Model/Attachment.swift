import Foundation
#if os(iOS) || os(tvOS)
import MobileCoreServices
#elseif os(macOS)
import CoreServices
#endif

struct Attachment {
    let data: Data
    let name: String
    let mimeType: String

    // Make sure attachments are not bigger than 10 MB.
    private static let maximumAttachmentSize = 10 * 1024 * 1024
    
    init?(filePath: String) {
        do {
            let fileURL = URL(fileURLWithPath: filePath)
            
            let fileAttributes: [FileAttributeKey : Any] = try FileManager.default.attributesOfItem(atPath: filePath)
            
            if let fileSize = fileAttributes[FileAttributeKey.size] as? UInt64,
               Attachment.maximumAttachmentSize >= fileSize,
               let fileData = try? Data(contentsOf: fileURL,
                                              options: Data.ReadingOptions.mappedIfSafe) {
                mimeType = Attachment.mimeTypeForPath(fileUrl: fileURL)
                name = "attachment_" + (fileURL.lastPathComponent as NSString).deletingPathExtension + "_\(arc4random())"
                data = fileData
            } else {
                return nil
            }
        } catch  {
            return nil
        }
    }

    static private func mimeTypeForPath(fileUrl: URL) -> String {
        guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                              fileUrl.pathExtension as NSString, nil)?
            .takeRetainedValue(),
            let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?
                .takeRetainedValue() as String? else { return "application/octet-stream" }
        return mimetype
    }
}
