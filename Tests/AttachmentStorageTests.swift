import Foundation
import Testing
@testable import Backtrace

@Suite(.serialized) struct AttachmentStorageTests {

    func createAFile() throws -> URL {
        let fileName = "sample"
        let dirName = "directory"
        guard let libraryDirectoryUrl = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            throw FileError.fileNotWritten
        }
        let directoryUrl = libraryDirectoryUrl.appendingPathComponent(dirName)
        try? FileManager().createDirectory(
                    at: directoryUrl,
                    withIntermediateDirectories: false,
                    attributes: nil
                )
        let fileUrl = directoryUrl.appendingPathComponent(fileName).appendingPathExtension("txt")

        return fileUrl
    }

    @Test func canSaveAttachmentsAsPlist() throws {
        var crashAttachments = Attachments()
        let storage = ReportMetadataStorageMock.self
        let bookmarkHandler = AttachmentBookmarkHandlerMock.self

        guard let fileUrl = try? createAFile() else {
            throw FileError.fileNotWritten
        }
        crashAttachments.append(fileUrl)

        let attachmentsFileName = "attachments"
        try? AttachmentsStorage.store(crashAttachments,
                                      fileName: attachmentsFileName,
                                      storage: storage,
                                      bookmarkHandler: bookmarkHandler)

        let attachments =
            (try? AttachmentsStorage.retrieve(fileName: attachmentsFileName,
                                              storage: storage,
                                              bookmarkHandler: bookmarkHandler)) ?? Attachments()
        let attachmentPaths = attachments.map(\.path)

        #expect(attachmentPaths != nil)
        #expect(attachmentPaths.count == 1)
        #expect(attachmentPaths[0] == fileUrl.path)
    }

    @Test func canWorkWithEmptyAttachments() {
        let crashAttachments = Attachments()
        let storage = ReportMetadataStorageMock.self
        let bookmarkHandler = AttachmentBookmarkHandlerMock.self

        let attachmentsFileName = "attachments"
        try? AttachmentsStorage.store(crashAttachments,
                                      fileName: attachmentsFileName,
                                      storage: storage,
                                      bookmarkHandler: bookmarkHandler)

        let attachments =
            (try? AttachmentsStorage.retrieve(fileName: attachmentsFileName,
                                              storage: storage,
                                              bookmarkHandler: bookmarkHandler)) ?? Attachments()
        let attachmentPaths = attachments.map(\.path)

        #expect(attachmentPaths != nil)
        #expect(attachmentPaths.count == 0)
    }
}
