import Testing
@testable import Backtrace
import Foundation

@Suite("Dispatcher")
struct DispatcherTests {

    @Test("Dispatcher operation calls the completion closure")
    func dispatcherCallsCompletionClosure() {
        let dispatcher = Dispatcher()
        var dispatched = false
        dispatcher.dispatch({
            dispatched = true
        }, completion: {
            // spec will be updated after upgrading Quick & Nimble to resolve Fastlane hangs
            #expect(dispatched == true)
        })
    }
}
