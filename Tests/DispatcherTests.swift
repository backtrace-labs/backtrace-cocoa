import XCTest

import Nimble
import Quick
@testable import Backtrace

final class DispatcherTests: QuickSpec {

    override func spec() {
        describe("Dispatcher") {
            let dispatcher = Dispatcher()
            var dispatched = false
            context("Dispatcher operation") {
                it("calls the completion closure") {
                    dispatcher.dispatch({
                        dispatched = true
                    }, completion: {
                        expect(dispatched).to(beTrue())
                    })
                }
            }
        }
    }
}
