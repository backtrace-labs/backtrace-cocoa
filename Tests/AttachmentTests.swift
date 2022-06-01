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
                let bundle = Bundle(for: type(of: self))
#if SWIFT_PACKAGE
         let path = Bundle.module.path(forResource:"test", ofType:"txt")
#else
         let path = bundle.path(forResource: "test", ofType: "txt")
#endif
                if let path = path {
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
            }
        }
    }
}
