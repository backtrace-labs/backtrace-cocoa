import Foundation

protocol AttachmentBookmarkHandler {
    static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks
    static func extractAttachmentUrls(_ bookmarks: Bookmarks) throws -> Attachments
}

enum AttachmentBookmarkHandlerImpl: AttachmentBookmarkHandler {
    static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks {
        var attachmentsBookmarksDict = Bookmarks()
        for attachment in attachments {
            do {
                let bookmark = try attachment.bookmarkData(options: .minimalBookmark)
                attachmentsBookmarksDict[attachment.path] = bookmark
            } catch {
                BacktraceLogger.error("Could not bookmark attachment file URL. Error: \(error)")
                continue
            }
        }
        return attachmentsBookmarksDict
    }

    static func extractAttachmentUrls(_ bookmarks: Bookmarks) throws -> Attachments {
        var attachments = Attachments()
        for bookmark in bookmarks {
            var stale = Bool(false)
            let fileUrl: URL
            do {
                fileUrl = try URL(resolvingBookmarkData: bookmark.value,
                                  options: URL.BookmarkResolutionOptions(),
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale)
            } catch {
                BacktraceLogger.error("Could not resolve file URL from bookmark: \(error)")
                throw AttachmentsStorageError.invalidBookmark
            }
            guard !stale else {
                BacktraceLogger.error("Bookmark data is stale. Refusing to partially restore attachments.")
                throw AttachmentsStorageError.invalidBookmark
            }
            attachments.append(fileUrl)
        }
        return attachments
    }
}
