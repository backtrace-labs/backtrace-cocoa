import Foundation
import XCTest
@testable import Backtrace

class BacktraceObserverMock: BacktraceNotificationHandlerDelegate {

    var delegate: BacktraceNotificationObserverDelegate?

    var startObservingCalled = false

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        startObservingCalled = true
    }
}
