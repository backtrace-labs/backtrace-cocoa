import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttributesTests: QuickSpec {
    
    override func spec() {
        describe("Collecting attributes") {
            it("Collects default attributes", closure: {
                let attributesProvider = AttributesProvider()
                
                expect(attributesProvider.defaultAttributes).toNot(beEmpty())
                expect(attributesProvider.attributes).toNot(beEmpty())
                expect(attributesProvider.userAttributes).to(beEmpty())
            })
            
            it("Appends client attribute", closure: {
                let attributesProvider = AttributesProvider()
                attributesProvider.userAttributes["foo"] = "bar"
                
                expect(attributesProvider.defaultAttributes).toNot(beEmpty())
                expect(attributesProvider.attributes).toNot(beEmpty())
                expect(attributesProvider.userAttributes).toNot(beEmpty())
            })
        }
    }
}
