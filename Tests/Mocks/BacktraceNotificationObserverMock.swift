import Foundation
import XCTest
@testable import Backtrace

class BacktraceOrientationNotificationObserverMock: BacktraceNotificationHandlerDelegate {

    var delegate: BacktraceNotificationObserverDelegate?

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
    }

    func addOrientationBreadcrumb(_ orientation: String) {
        let attributes = ["orientation": orientation]
        delegate?.addBreadcrumb("Orientation changed",
                                attributes: attributes,
                                type: .system,
                                level: .info)
    }
}

class BacktraceBatteryNotificationObserverMock: BacktraceNotificationHandlerDelegate {

    var delegate: BacktraceNotificationObserverDelegate?

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
    }

    func addBatteryBreadcrumb(_ batteryLevel: Int) {
        delegate?.addBreadcrumb("full battery level : \(batteryLevel)%",
                                attributes: nil,
                                type: .system,
                                level: .info)
    }
}

class BacktraceMemoryNotificationObserverMock: BacktraceNotificationHandlerDelegate {

    var delegate: BacktraceNotificationObserverDelegate?

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
    }

    func addMemoryBreadcrumb(_ message: String) {
        delegate?.addBreadcrumb(message,
                                attributes: nil,
                                type: .system,
                                level: .info)
    }
}
