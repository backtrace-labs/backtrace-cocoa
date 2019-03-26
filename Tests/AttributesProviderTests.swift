import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttributesProviderTests: QuickSpec {
    
    override func spec() {
        describe("Attributes provider") {
            it("has default values", closure: {
                let attributesProvider = AttributesProvider()
                
                expect(attributesProvider.defaultAttributes).toNot(beEmpty())
                expect(attributesProvider.attributes).toNot(beEmpty())
                expect(attributesProvider.userAttributes).to(beEmpty())
            })
            
            it("allows the user add new attributes", closure: {
                let attributesProvider = AttributesProvider()
                attributesProvider.userAttributes["foo"] = "bar"
                
                expect(attributesProvider.defaultAttributes).toNot(beEmpty())
                expect(attributesProvider.attributes).toNot(beEmpty())
                expect(attributesProvider.userAttributes).toNot(beEmpty())
            })
        }
    }
}
