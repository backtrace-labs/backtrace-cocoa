import Foundation
import Testing

@testable import Backtrace

/// Polling helper that replaces Nimble's `toEventually`.
private func pollUntil(maxAttempts: Int = 50,
                       interval: TimeInterval = 0.1,
                       condition: () -> Bool) {
    for _ in 0..<maxAttempts {
        if condition() { return }
        Thread.sleep(forTimeInterval: interval)
    }
}

private class BundleToken {}

@Suite("Attachments")
struct AttachmentTests {

    @Test("Cannot be created from non-existing file")
    func cannotCreateFromNonExistingFile() {
        #expect(Attachment(filePath: "") == nil)
    }

    @Test("Can be created from existing file")
    func canCreateFromExistingFile() {
#if SWIFT_PACKAGE
        let path = Bundle.module.path(forResource: "test", ofType: "txt")
#else
        let bundle = Bundle(for: BundleToken.self)
        let path = bundle.path(forResource: "test", ofType: "txt")
#endif
        if let path {
            #expect(Attachment(filePath: path) != nil)
        } else {
            Issue.record("Could not find test.txt resource")
        }
    }

    @Test("Has mime type: text/plain")
    func hasMimeTypeTextPlain() {
#if SWIFT_PACKAGE
        let path = Bundle.module.path(forResource: "test", ofType: "txt")
#else
        let bundle = Bundle(for: BundleToken.self)
        let path = bundle.path(forResource: "test", ofType: "txt")
#endif
        if let path = path, let attachment = Attachment(filePath: path) {
            #expect(attachment.mimeType == "text/plain")
            #expect(attachment.data != nil)
            #expect(attachment.filename.contains("attachment_test"))
        } else {
            Issue.record("Could not create attachment from test.txt resource")
        }
    }

    @Test("Attachment won't init if size is larger than 10 MB")
    func attachmentWontInitIfSizeLargerThan10MB() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("11mb.file").path

        try NSMutableData(bytes: [], length: 11 * 1024 * 1024).write(toFile: path)
        #expect(FileManager.default.fileExists(atPath: path))

        // test reliability, without this test fails intermittently
        let fileSize = try FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64
        pollUntil { (fileSize ?? 0) > UInt64(10 * 1024 * 1024) }
        #expect((fileSize ?? 0) > UInt64(10 * 1024 * 1024))

        let attachment = Attachment(filePath: path)
        #expect(attachment == nil)
        try FileManager.default.removeItem(atPath: path)
    }
}
