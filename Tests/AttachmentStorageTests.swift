import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttachmentStorageTests: QuickSpec {

    override func spec() {
        describe("AttachmentStorage") {
            it("can save attachments as a plist") {
                var crashAttachments = Attachments()
                let storage = ReportMetadataStorageMock.self
                let bookmarkHandler = AttachmentBookmarkHandlerMock.self

                guard let fileUrl = try? self.createAFile() else {
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

                expect(attachmentPaths).toNot(beNil())
                expect(attachmentPaths.count).to(be(1))
                expect(attachmentPaths[0]).to(equal(fileUrl.path))
            }
            it("can work with empty attachments") {
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

                expect(attachmentPaths).toNot(beNil())
                expect(attachmentPaths.count).to(be(0))
            }
        }
    }

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
}
