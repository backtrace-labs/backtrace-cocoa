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
        let fileURL = URL(fileURLWithPath: filePath)

        // Don't allow too large attachments
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = fileAttributes[FileAttributeKey.size] as? UInt64,
              fileSize < Attachment.maximumAttachmentSize else {
            BacktraceLogger.warning("Skipping attachment because fileSize couldn't be read or is larger than 10MB: \(filePath)")
            return nil
        }

        do {
            data = try Data(contentsOf: fileURL, options: Data.ReadingOptions.mappedIfSafe)
        } catch {
            BacktraceLogger.warning("Skipping attachment: \(filePath): \(error.localizedDescription)")
            return nil
        }

        mimeType = Attachment.mimeTypeForPath(fileUrl: fileURL)
        name = "attachment_" + (fileURL.lastPathComponent as NSString).deletingPathExtension + "_\(arc4random())"
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
