import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttachmentTests: QuickSpec {

    override func spec() {
        describe("Attachments") {
            it("cannot be created from non-existing file") {
                expect(Attachment(filePath: "")).to(beNil())
            }

            it("can be created from existing file") {
                //let bundle = Bundle.module.url(for: type(of: self))
                
//                guard let path = Bundle.module.url(forResource: "test", withExtension: "txt") else {
//                    throw RepositoryError
//                        .persistentRepositoryInitError(details: "Couldn't find model url for name: \(momdName)")
//                }
//
                
                //let path = bundle.path(forResource: "test", ofType: "txt")
                if let path = Bundle.module.path(forResource: "test", ofType: "txt") {
                    expect(Attachment(filePath: path)).toNot(beNil())
                } else {
                    fail()
                }
            }

            context("Attachment exists") {
                let bundle = Bundle(for: type(of: self))
                let path = bundle.path(forResource: "test", ofType: "txt")
                if let path = path, let attachment = Attachment(filePath: path) {
                    it("has mime type: text/plain") {
                        expect(attachment.mimeType).to(equal("text/plain"))
                        expect(attachment.data).toNot(beNil())
                        expect(attachment.name).to(contain(["attachment_test_"]))
                    }
                } else {
                    fail()
                }

                throwingIt("attachment won't init if size is larger than 10 MB") {
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("11mb.file").path

                    try NSMutableData.init(bytes: [], length: 11 * 1024 * 1024).write(toFile: path)
                    expect { FileManager.default.fileExists(atPath: path)}.to(beTrue())

                    // test reliability, without this test fails intermittently
                    let fileSize = try FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64
                    expect { fileSize }.toEventually(beGreaterThan(10 * 1024 * 1024))

                    let attachment = Attachment(filePath: path)
                    expect(attachment).to(beNil())
                    try FileManager.default.removeItem(atPath: path)
                }
            }
        }
    }
}
