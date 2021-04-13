import Foundation
import XCTest
@testable import Backtrace

enum AttachmentBookmarkHandlerMock: AttachmentBookmarkHandler {
    static func convertAttachmentUrlsToBookmarks(_ attachments: Attachments) throws -> Bookmarks {
        var attachmentsBookmarksDict = Bookmarks()
        for attachment in attachments {
            attachmentsBookmarksDict[attachment.key] = attachment.value.path.data(using: .utf8)
        }
        return attachmentsBookmarksDict
    }
    
    static func extractAttachmentUrls(_ bookmarks: Bookmarks) throws -> Attachments {
        var attachments = Attachments()
        for bookmark in bookmarks {
            attachments[bookmark.key] = URL(string: String(data: bookmark.value, encoding: .utf8) ?? String())
        }
        return attachments
    }
}
