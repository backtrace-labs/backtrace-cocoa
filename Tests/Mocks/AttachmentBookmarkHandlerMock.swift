import Foundation
import XCTest
@testable import Backtrace

enum AttachmentsBookmarkError: Error {
    case invalidUrl
}

enum AttachmentBookmarkHandlerMock: AttachmentBookmarkHandler {
    static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks {
        var attachmentsBookmarksDict = Bookmarks()
        for attachment in attachments {
            attachmentsBookmarksDict[attachment.path] = attachment.path.data(using: .utf8)
        }
        return attachmentsBookmarksDict
    }

    static func extractAttachmentUrls(_ bookmarks: Bookmarks) throws -> Attachments {
        var attachments = Attachments()
        for bookmark in bookmarks {
            guard let fileUrl = URL(string: String(data: bookmark.value, encoding: .utf8) ?? String()) else {
                throw AttachmentsBookmarkError.invalidUrl
            }
            attachments.append(fileUrl)
        }
        return attachments
    }
}
