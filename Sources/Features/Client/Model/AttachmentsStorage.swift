import Foundation

/// Type-alias of storing file attachments on disk (as a bookmark)
/// Expected format: Filename, File URL bookmark
public typealias Bookmarks = [String: NSData]

final class AttachmentsStorage {
    struct Config {
        let cacheUrl: URL
        let directoryUrl: URL
        let fileUrl: URL
        
        init(fileName: String) throws {
            guard let cacheDirectoryURL =
                FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    throw FileError.noCacheDirectory
            }
            self.cacheUrl = cacheDirectoryURL
            self.directoryUrl = cacheDirectoryURL.appendingPathComponent(directoryName)
            self.fileUrl = directoryUrl.appendingPathComponent("\(fileName)_attachments.plist")
        }
    }
    
    private static let directoryName = Bundle(for: AttachmentsStorage.self).bundleIdentifier ?? "BacktraceCache"
    
    static func store(_ attachments: Attachments, fileName: String) throws {
        let config = try Config(fileName: fileName)
        
        if !FileManager.default.fileExists(atPath: config.directoryUrl.path) {
            try FileManager.default.createDirectory(atPath: config.directoryUrl.path,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        }
        
        let attachmentBookmarks = try convertAttachmentUrlsToBookmarks(attachments)
        
        if #available(iOS 11.0, tvOS 11.0, macOS 10.13, *) {
            try (attachmentBookmarks as NSDictionary).write(to: config.fileUrl)
        } else {
            guard (attachmentBookmarks as NSDictionary).write(to: config.fileUrl, atomically: true) else {
                throw FileError.fileNotWritten
            }
        }
        BacktraceLogger.debug("Stored attachments at path: \(config.fileUrl)")
    }
    
    static func retrieve(fileName: String) throws -> Attachments {
        let config = try Config(fileName: fileName)
        guard FileManager.default.fileExists(atPath: config.fileUrl.path) else {
            throw FileError.fileNotExists
        }
        // load file to NSDictionary
        let dictionary: NSDictionary
        if #available(iOS 11.0, tvOS 11.0, macOS 10.13, *) {
            dictionary = try NSDictionary(contentsOf: config.fileUrl, error: ())
        } else {
            guard let dictionaryFromFile = NSDictionary(contentsOf: config.fileUrl) else {
                throw FileError.invalidPropertyList
            }
            dictionary = dictionaryFromFile
        }
        
        guard let bookmarks = dictionary as? Bookmarks else {
            BacktraceLogger.debug("Could not convert stored dictionary to Bookmarks type")
            throw FileError.unsupportedScheme
        }
        guard let attachments = try? extractAttachmentUrls(bookmarks) else {
            BacktraceLogger.debug("Could not extract attachment URLs from stored attachments Bookmarks")
            throw FileError.invalidPropertyList
        }

        BacktraceLogger.debug("Retrieved attachments from path: \(config.fileUrl)")
        return attachments
    }
    
    static func retrieveAsArray(fileName: String) throws -> [String] {
        guard let attachments = try? retrieve(fileName: fileName) else {
            return []
        }
        var attachmentsArray = [ String ]()
        for attachment in attachments {
            attachmentsArray.append(attachment.value.path)
        }
        return attachmentsArray
    }
    
    static func remove(fileName: String) throws {
        let config = try Config(fileName: fileName)
        // check file exists
        guard FileManager.default.fileExists(atPath: config.fileUrl.path) else {
            throw FileError.fileNotExists
        }
        // remove file
        try FileManager.default.removeItem(at: config.fileUrl)
        // TODO: Delete file attachment copy
        BacktraceLogger.debug("Removed attachments plist at path: \(config.fileUrl)")
    }
    
    private static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks {
        var attachmentsBookmarksDict = Bookmarks()
        for attachment in attachments {
            do { let bookmark = try attachment.value.bookmarkData(options: URL.BookmarkCreationOptions.minimalBookmark)
                attachmentsBookmarksDict[attachment.key] = bookmark as NSData
            } catch {
                print("Caught error: \(error)")
                BacktraceLogger.error("Could not bookmark attachment file URL")
                continue
            }
        }
        return attachmentsBookmarksDict
    }
    
    private static func extractAttachmentUrls(_ bookmarks: Bookmarks) throws -> Attachments {
        var attachments = Attachments()
        for bookmark in bookmarks {
            var stale = ObjCBool(false)
            guard let fileUrl = try? NSURL.init(resolvingBookmarkData: bookmark.value as Data,
                                                options: NSURL.BookmarkResolutionOptions(),
                                                relativeTo: nil,
                                                bookmarkDataIsStale: &stale) else {
                BacktraceLogger.error("Could not resolve file URL from bookmark")
                continue
            }
            if stale.boolValue {
                BacktraceLogger.error("Bookmark data is stale. This should not happen")
            }
            attachments[bookmark.key] = fileUrl as URL
        }
        return attachments
    }
}
