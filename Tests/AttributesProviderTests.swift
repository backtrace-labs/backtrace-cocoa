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
                expect(attributesProvider.allAttributes).toNot(beEmpty())
                expect(attributesProvider.attributes).to(beEmpty())
            })
            
            it("allows the user add new attributes", closure: {
                let attributesProvider = AttributesProvider()
                attributesProvider.attributes["foo"] = "bar"
                
                expect(attributesProvider.defaultAttributes).toNot(beEmpty())
                expect(attributesProvider.allAttributes).toNot(beEmpty())
                expect(attributesProvider.attributes).toNot(beEmpty())
            })
        }
    }
}
