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
                        // spec will be updated after upgrading Quick & Nimble to resolve Fastlane hangs
                        expect(dispatched).to(beTrue())
                    })
                }

                it("completes without running work when dispatch races after shutdown") {
                    let stoppedDispatcher = Dispatcher()
                    let completionCalled = DispatchSemaphore(value: 0)
                    var rejectedWorkRan = false
                    stoppedDispatcher.shutdown()

                    stoppedDispatcher.dispatch({
                        rejectedWorkRan = true
                    }, completion: {
                        completionCalled.signal()
                    })

                    expect(completionCalled.wait(timeout: .now() + .seconds(1))).to(equal(.success))
                    expect(rejectedWorkRan).to(beFalse())
                }
            }
        }
    }
}
