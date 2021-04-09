import Foundation

/// Type-alias of storing file attachments on disk (as a bookmark)
/// Expected format: Filename, File URL bookmark
private typealias Bookmarks = [String: Data]

enum AttachmentsStorageError: Error {
    case invalidDictionary
    case invalidBookmark
}

enum AttachmentsStorage: ReportMetadataStorage {
    struct AttachmentsConfig: Config {
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
    
    private static let directoryName = Bundle.main.bundleIdentifier ?? "BacktraceCache"
    
    static func store(_ attachments: Attachments, fileName: String) throws {
        let config = try AttachmentsConfig(fileName: fileName)
        let attachmentBookmarks = try convertAttachmentUrlsToBookmarks(attachments)
        try storeToFile(attachmentBookmarks as NSDictionary, config: config)
        BacktraceLogger.debug("Stored attachments paths at path: \(config.fileUrl)")
    }
    
    static func retrieve(fileName: String) throws -> Attachments {
        let config = try AttachmentsConfig(fileName: fileName)
        let dictionary = try retrieveFromFile(config: config)
        
        guard let bookmarks = dictionary as? Bookmarks else {
            BacktraceLogger.debug("Could not convert stored dictionary to Bookmarks type")
            throw AttachmentsStorageError.invalidDictionary
        }
        guard let attachments = try? extractAttachmentUrls(bookmarks) else {
            BacktraceLogger.debug("Could not extract attachment URLs from stored attachments Bookmarks")
            throw AttachmentsStorageError.invalidBookmark
        }

        BacktraceLogger.debug("Retrieved attachment paths at path: \(config.fileUrl)")
        return attachments
    }
    
    static func remove(fileName: String) throws {
        let config = try AttachmentsConfig(fileName: fileName)
        try removeFile(config: config)
        BacktraceLogger.debug("Removed attachments paths at path: \(config.fileUrl)")
    }
    
    private static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks {
        var attachmentsBookmarksDict = Bookmarks()
        for attachment in attachments {
            do {
                let bookmark = try attachment.value.bookmarkData(options: URL.BookmarkCreationOptions.minimalBookmark)
                attachmentsBookmarksDict[attachment.key] = bookmark
            } catch {
                BacktraceLogger.error("Could not bookmark attachment file URL. Error: \(error)")
                continue
            }
        }
        return attachmentsBookmarksDict
    }
    
    private static func extractAttachmentUrls(_ bookmarks: Bookmarks) throws -> Attachments {
        var attachments = Attachments()
        for bookmark in bookmarks {
            var stale = Bool(false)
            guard let fileUrl = try? URL(resolvingBookmarkData: bookmark.value,
                                         options: URL.BookmarkResolutionOptions(),
                                         relativeTo: nil,
                                         bookmarkDataIsStale: &stale) else {
                BacktraceLogger.error("Could not resolve file URL from bookmark")
                continue
            }
            if stale {
                BacktraceLogger.error("Bookmark data is stale. This should not happen")
                continue
            }
            attachments[bookmark.key] = fileUrl
        }
        return attachments
    }
}
