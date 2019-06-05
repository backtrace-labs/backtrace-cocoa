import XCTest

import Nimble
import Quick
@testable import Backtrace

final class AttributesProviderTests: QuickSpec {
    
    override func spec() {
        describe("Attributes provider") {
            it("has default values", closure: {
                let attributesProvider = AttributesProvider()
                
                expect(attributesProvider.defaultAttributes.isEmpty).to(beFalse())
                expect(attributesProvider.attributes.isEmpty).to(beTrue())
                expect(attributesProvider.allAttributes.isEmpty).to(beFalse())
            })

            it("allows the user add new attributes", closure: {
                let attributesProvider = AttributesProvider()
                attributesProvider.attributes["foo"] = "bar"

                expect(attributesProvider.defaultAttributes.isEmpty).to(beFalse())
                expect(attributesProvider.allAttributes.isEmpty).to(beFalse())
                expect(attributesProvider.attributes.isEmpty).to(beFalse())
            })
        }
    }
}
