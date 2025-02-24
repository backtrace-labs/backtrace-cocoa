import Foundation
import UniformTypeIdentifiers
#if (os(iOS) || os(tvOS))
import MobileCoreServices
#elseif os(macOS)
import CoreServices
#endif

struct Attachment {
    let data: Data
    /// File name with extension that represents the real file name
    let filename: String
    
    /// MIME type of the file
    let mimeType: String
    
    /// Maximum allowed size for attachments (10 MB)
    private static let maximumAttachmentSize = 10 * 1024 * 1024
    
    /// Custom prefix for generated filenames
    private static let filenamePrefix = "attachment_"
    
    /// Initializes an Attachment from a file path
    /// - Parameter filePath: Path to the file
    init?(filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        
        // Ensure file size is within maximumAttachmentSize limits
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = fileAttributes[FileAttributeKey.size] as? UInt64,
              fileSize <= Attachment.maximumAttachmentSize else {
            BacktraceLogger.warning("Skipping attachment because fileSize couldn't be read or is larger than 10MB: \(filePath)")
            return nil
        }
        
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            BacktraceLogger.warning("Skipping attachment: \(filePath): \(error.localizedDescription)")
            return nil
        }
        
        mimeType = Attachment.mimeTypeForPath(fileUrl: fileURL)
        filename = Attachment.filenamePrefix + fileURL.lastPathComponent
    }
    
    /// Determines the MIME type for a file URL
    /// - Parameter fileUrl: File URL
    /// - Returns: MIME type as a string, or "application/octet-stream" as fallback
    static private func mimeTypeForPath(fileUrl: URL) -> String {
        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
            if let type = UTType(filenameExtension: fileUrl.pathExtension)?.preferredMIMEType {
                return type
            }
        } else {
            guard let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                  fileUrl.pathExtension as NSString, nil)?
                .takeRetainedValue(),
                  let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?
                .takeRetainedValue() as String? else { return "application/octet-stream" }
            return mimetype
        }
        return "application/octet-stream"
    }
}
