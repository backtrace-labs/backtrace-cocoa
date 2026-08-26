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

        init(fileName: String, directoryUrl explicitDirectoryUrl: URL? = nil) throws {
            if let explicitDirectoryUrl = explicitDirectoryUrl {
                self.cacheUrl = explicitDirectoryUrl
                self.directoryUrl = explicitDirectoryUrl
                self.fileUrl = explicitDirectoryUrl.appendingPathComponent("\(fileName)_attachments.plist")
                return
            }

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

    static func store(_ attachments: Attachments, fileName: String, directoryUrl: URL? = nil) throws {
        try store(attachments, fileName: fileName, directoryUrl: directoryUrl,
                  storage: ReportMetadataStorageImpl.self,
                  bookmarkHandler: AttachmentBookmarkHandlerImpl.self)
    }

    static func store<T: ReportMetadataStorage, U: AttachmentBookmarkHandler>
    (_ attachments: Attachments, fileName: String, storage: T.Type, bookmarkHandler: U.Type) throws {
        try store(attachments, fileName: fileName, directoryUrl: nil,
                  storage: storage, bookmarkHandler: bookmarkHandler)
    }

    static func store<T: ReportMetadataStorage, U: AttachmentBookmarkHandler>
    (_ attachments: Attachments, fileName: String, directoryUrl: URL?, storage: T.Type, bookmarkHandler: U.Type) throws {
        let config = try AttachmentsConfig(fileName: fileName, directoryUrl: directoryUrl)
        let attachmentBookmarks = try U.convertAttachmentUrlsToBookmarks(attachments)
        try T.storeToFile(attachmentBookmarks, config: config)
        BacktraceLogger.debug("Stored attachments paths at path: \(config.fileUrl)")
    }

    static func retrieve(fileName: String, directoryUrl: URL? = nil) throws -> Attachments {
        try retrieve(fileName: fileName, directoryUrl: directoryUrl,
                     storage: ReportMetadataStorageImpl.self,
                     bookmarkHandler: AttachmentBookmarkHandlerImpl.self)
    }

    static func retrieve<T: ReportMetadataStorage, U: AttachmentBookmarkHandler>
    (fileName: String, storage: T.Type, bookmarkHandler: U.Type) throws -> Attachments {
        try retrieve(fileName: fileName, directoryUrl: nil,
                     storage: storage, bookmarkHandler: bookmarkHandler)
    }

    static func retrieve<T: ReportMetadataStorage, U: AttachmentBookmarkHandler>
    (fileName: String, directoryUrl: URL?, storage: T.Type, bookmarkHandler: U.Type) throws -> Attachments {
        let config = try AttachmentsConfig(fileName: fileName, directoryUrl: directoryUrl)
        let dictionary = try T.retrieveFromFile(config: config)

        guard let bookmarks = dictionary as? Bookmarks else {
            BacktraceLogger.debug("Could not convert stored dictionary to Bookmarks type")
            throw AttachmentsStorageError.invalidDictionary
        }
        let attachments: Attachments
        do {
            attachments = try U.extractAttachmentUrls(bookmarks)
        } catch {
            BacktraceLogger.debug("Could not extract every attachment URL from stored attachment bookmarks: \(error)")
            throw AttachmentsStorageError.invalidBookmark
        }

        BacktraceLogger.debug("Retrieved attachment paths at path: \(config.fileUrl)")
        return attachments
    }

    static func remove(fileName: String, directoryUrl: URL? = nil) throws {
        try remove(fileName: fileName, directoryUrl: directoryUrl,
                   storage: ReportMetadataStorageImpl.self)
    }

    static func remove<T: ReportMetadataStorage>(fileName: String, storage: T.Type) throws {
        try remove(fileName: fileName, directoryUrl: nil, storage: storage)
    }

    static func remove<T: ReportMetadataStorage>(fileName: String,
                                                  directoryUrl: URL?,
                                                  storage: T.Type) throws {
        let config = try AttachmentsConfig(fileName: fileName, directoryUrl: directoryUrl)
        try T.removeFile(config: config)
        BacktraceLogger.debug("Removed attachments paths at path: \(config.fileUrl)")
    }
}
