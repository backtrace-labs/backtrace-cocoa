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

    init?(filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        guard let fileData = try? Data(contentsOf: fileURL,
                                       options: Data.ReadingOptions.mappedIfSafe) else { return nil }

        mimeType = Attachment.mimeTypeForPath(fileUrl: fileURL)
        name = "attachment_" + (fileURL.lastPathComponent as NSString).deletingPathExtension + "_\(arc4random())"
        data = fileData
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
