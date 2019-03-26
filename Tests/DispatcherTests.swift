import XCTest

import Nimble
import Quick
@testable import Backtrace

final class DispatcherTests: QuickSpec {
    
    override func spec() {
        describe("Dispatcher") {
            it("calls the completion closure", closure: {
                let dispatcher = Dispatcher()
                var closureCalled = false
                var finished = false
                dispatcher.dispatch({
                    closureCalled = true
                }, completion: {
                    finished = true
                })
                expect(finished).toEventually(beTrue(), timeout: 5, pollInterval: 0.1)
                expect(closureCalled).toEventually(beTrue(), timeout: 5, pollInterval: 0.1)
            })
        }
    }
}
