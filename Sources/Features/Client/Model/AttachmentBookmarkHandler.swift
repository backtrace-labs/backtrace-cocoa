import Foundation

protocol AttachmentBookmarkHandler {
    static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks
    static func extractAttachmentUrls(_ bookmarks: Bookmarks) throws -> Attachments
}

enum AttachmentBookmarkHandlerImpl: AttachmentBookmarkHandler {
    struct RecoveryResult {
        let attachments: Attachments
        let invalidBookmarkCount: Int
    }

    static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks {
        var attachmentsBookmarksDict = Bookmarks()
        for attachment in attachments {
            do {
                let bookmark = try attachment.bookmarkData(options: .minimalBookmark)
                attachmentsBookmarksDict[attachment.path] = bookmark
            } catch {
                BacktraceLogger.error("Could not bookmark an attachment file URL.")
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
                BacktraceLogger.error("Could not resolve an attachment file URL from its bookmark.")
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

    /// Recovers every independently valid bookmark from a crash-time sidecar.
    ///
    /// Pending crash attachments are optional enrichment. One damaged or stale bookmark must not prevent the crash payload itself from reaching durable storage.
    static func recoverAttachmentUrls(_ bookmarks: Bookmarks) -> RecoveryResult {
        var attachments = Attachments()
        var invalidBookmarkCount = 0

        for bookmark in bookmarks {
            var stale = false
            do {
                let fileUrl = try URL(resolvingBookmarkData: bookmark.value,
                                      options: URL.BookmarkResolutionOptions(),
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale)
                guard !stale else {
                    invalidBookmarkCount += 1
                    continue
                }
                attachments.append(fileUrl)
            } catch {
                invalidBookmarkCount += 1
            }
        }

        return RecoveryResult(attachments: attachments,
                              invalidBookmarkCount: invalidBookmarkCount)
    }
}
