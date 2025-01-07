import Foundation

enum AttachmentsStorageError: Error {
    case invalidDictionary
    case invalidBookmark
}

enum AttachmentsStorage {
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

    static func store(_ attachments: Attachments, fileName: String) async throws {
        try await store(attachments, fileName: fileName, storage: ReportMetadataStorageImpl.self,
                  bookmarkHandler: AttachmentBookmarkHandlerImpl.self)
    }

    static func store<T: ReportMetadataStorage, U: AttachmentBookmarkHandler>
    (_ attachments: Attachments, fileName: String, storage: T.Type, bookmarkHandler: U.Type) async throws {
        let config = try AttachmentsConfig(fileName: fileName)
        let attachmentBookmarks = try await U.convertAttachmentUrlsToBookmarks(attachments)
        try T.storeToFile(attachmentBookmarks, config: config)
        await BacktraceLogger.debug("Stored attachments paths at path: \(config.fileUrl)")
    }

    static func retrieve(fileName: String) async throws -> Attachments {
        try await retrieve(fileName: fileName, storage: ReportMetadataStorageImpl.self,
                     bookmarkHandler: AttachmentBookmarkHandlerImpl.self)
    }

    static func retrieve<T: ReportMetadataStorage, U: AttachmentBookmarkHandler>
    (fileName: String, storage: T.Type, bookmarkHandler: U.Type) async throws -> Attachments {
        let config = try AttachmentsConfig(fileName: fileName)
        let dictionary = try T.retrieveFromFile(config: config)

        guard let bookmarks = dictionary as? Bookmarks else {
            await BacktraceLogger.debug("Could not convert stored dictionary to Bookmarks type")
            throw AttachmentsStorageError.invalidDictionary
        }
        guard let attachments = try? await U.extractAttachmentUrls(bookmarks) else {
            await BacktraceLogger.debug("Could not extract attachment URLs from stored attachments Bookmarks")
            throw AttachmentsStorageError.invalidBookmark
        }

        await BacktraceLogger.debug("Retrieved attachment paths at path: \(config.fileUrl)")
        return attachments
    }

    static func remove(fileName: String) async throws {
        try await remove(fileName: fileName, storage: ReportMetadataStorageImpl.self)
    }

    static func remove<T: ReportMetadataStorage>(fileName: String, storage: T.Type) async throws {
        let config = try AttachmentsConfig(fileName: fileName)
        try T.removeFile(config: config)
        await BacktraceLogger.debug("Removed attachments paths at path: \(config.fileUrl)")
    }
}
