import Foundation
import XCTest
@testable import Backtrace

#if os(iOS) || os(OSX) || targetEnvironment(macCatalyst)
class BacktraceObserverMock: BacktraceNotificationHandlerDelegate {

    var delegate: BacktraceNotificationObserverDelegate?

    var startObservingCalled = false
    var stopObservingCalled = false

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        startObservingCalled = true
    }

    func stopObserving() {
        delegate = nil
        stopObservingCalled = true
    }
}
#endif
