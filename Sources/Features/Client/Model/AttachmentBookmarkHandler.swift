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
            attachments.append(fileUrl)
        }
        return attachments
    }
}
