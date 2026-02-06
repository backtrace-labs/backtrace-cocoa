// swiftlint:disable function_body_length type_body_length file_length
import Foundation
import Testing

@testable import Backtrace

#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import CallKit

// MARK: - iOS Mock Classes

private class OverriddenOrientationNotificationObsrvr: BacktraceOrientationNotificationObserver {
    var mockOrientation: UIDeviceOrientation?

    override var orientation: UIDeviceOrientation { mockOrientation ?? super.orientation }
}

private class OverriddenBatteryNotificationObserveriOS: BacktraceBatteryNotificationObserver {
    var mockBatteryLevel: Float?
    var mockBatteryState: UIDevice.BatteryState?

    override var batteryLevel: Float { mockBatteryLevel ?? super.batteryLevel }
    override var batteryState: UIDevice.BatteryState { mockBatteryState ?? super.batteryState }
}

private class OverriddenCallNotificationObserver: BacktraceCallNotificationObserver {
    var mockIsOutgoingCall: Bool?
    var mockHasConnectedCall: Bool?
    var mockHasEndedCall: Bool?

    override var isOutgoingCall: Bool { mockIsOutgoingCall ?? super.isOutgoingCall }
    override var hasConnectedCall: Bool { mockHasConnectedCall ?? super.hasConnectedCall }
    override var hasEndedCall: Bool { mockHasEndedCall ?? super.hasEndedCall }
}
#endif

#if os(macOS)
// MARK: - macOS Mock Classes

private class OverriddenMemoryNotificationObserver: BacktraceMemoryNotificationObserver {
    var mockMemoryPressureEvent: DispatchSource.MemoryPressureEvent?

    override var memoryPressureEvent: DispatchSource.MemoryPressureEvent? {
        mockMemoryPressureEvent ?? super.memoryPressureEvent
    }
}

private class OverriddenBatteryNotificationObserverMac: BacktraceBatteryNotificationObserver {
    var isMockCharging: Bool?
    var mockBatteryLevel: Int?

    override var isCharging: Bool? {
        return isMockCharging ?? super.isCharging
    }

    override var batteryLevel: Int? {
        return mockBatteryLevel ?? super.batteryLevel
    }
}
#endif

// MARK: - Helpers

private let breadcrumbLogFileName = "bt-breadcrumbs-0"

private func breadcrumbLogPath(_ create: Bool) throws -> String {
    var fileURL = try FileManager.default.url(for: .documentDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil,
                                              create: create)
    fileURL.appendPathComponent(breadcrumbLogFileName)
    return fileURL.path
}

private func readBreadcrumbText() -> String? {
    do {
        let path = try breadcrumbLogPath(true)
        let fileURL = URL(fileURLWithPath: path)
        let content = try String(contentsOf: fileURL, encoding: .ascii)
        return content
    } catch {
        return nil
    }
}

private func countOccurrencesOfSubstring(str: String?, substr: String) -> Int {
    guard let str = str else {
        return 0
    }
    return { $0.isEmpty ? 0 : $0.count - 1 }( str.components(separatedBy: substr))
}

/// Polling helper that replaces Nimble's `toEventually`.
/// Polls up to `maxAttempts` times with `interval` seconds between each attempt.
private func pollUntil(maxAttempts: Int = 50,
                       interval: TimeInterval = 0.1,
                       condition: () -> Bool) {
    for _ in 0..<maxAttempts {
        if condition() { return }
        Thread.sleep(forTimeInterval: interval)
    }
}

// MARK: - All Breadcrumb Tests (serialized to avoid shared state conflicts)

@Suite("Breadcrumb Tests", .serialized)
struct AllBreadcrumbTests {

// MARK: - BreadcrumbsLogManager Tests

@Suite("BreadcrumbsLogManager")
struct BreadcrumbsLogManagerTests {

    @Test("Clears the file")
    func clearsTheFile() throws {
        let setting = BacktraceBreadcrumbSettings(maxQueueFileSizeBytes: 8192)
        let manager = try BacktraceBreadcrumbsLogManager(breadcrumbSettings: setting)
        _ = manager.clear()

        #expect(manager.addBreadcrumb("this is a Breadcrumb",
                                       attributes: nil,
                                       type: BacktraceBreadcrumbType.system,
                                       level: BacktraceBreadcrumbLevel.debug) == true)

        #expect(readBreadcrumbText()?.contains("this is a Breadcrumb") == true)

        #expect(manager.clear() == true)

        #expect(readBreadcrumbText()?.contains("this is a Breadcrumb") != true)

        #expect(manager.addBreadcrumb("this is a Breadcrumb",
                                       attributes: nil,
                                       type: BacktraceBreadcrumbType.system,
                                       level: BacktraceBreadcrumbLevel.debug) == true)

        #expect(readBreadcrumbText()?.contains("this is a Breadcrumb") == true)
    }
}

// MARK: - BacktraceBreadcrumbs Tests

@Suite("BacktraceBreadcrumbs")
struct BacktraceBreadcrumbsTests {

    private func makeBreadcrumbs() -> BacktraceBreadcrumbs {
        return BacktraceBreadcrumbs()
    }

    private func cleanUp(_ breadcrumbs: BacktraceBreadcrumbs) {
        _ = breadcrumbs.clear()
        breadcrumbs.disableBreadcrumbs()
    }

    // MARK: Not enabled

    @Test("Fails to add breadcrumb when not enabled")
    func failsToAddBreadcrumbWhenNotEnabled() {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        breadcrumbs.disableBreadcrumbs()
        #expect(!breadcrumbs.isBreadcrumbsEnabled)
        #expect(breadcrumbs.getCurrentBreadcrumbId == nil)
        #expect(!breadcrumbs.addBreadcrumb("Breadcrumb submit test"))
        #expect(readBreadcrumbText()?.contains("Breadcrumb submit test") != true)
    }

    // MARK: Enabled - level filtering

    @Test("Fails to add breadcrumb for lower breadcrumb level")
    func failsToAddBreadcrumbForLowerLevel() {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        breadcrumbs.enableBreadcrumbs(BacktraceBreadcrumbSettings(breadcrumbLevel: BacktraceBreadcrumbLevel.error))
        #expect(!breadcrumbs.allowBreadcrumbsToAdd(.info))
        #expect(!breadcrumbs.addBreadcrumb("Info Breadcrumb", level: .info))
        #expect(readBreadcrumbText()?.contains("Info Breadcrumb") != true)
    }

    @Test("Able to add breadcrumb for higher breadcrumb level")
    func ableToAddBreadcrumbForHigherLevel() {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        breadcrumbs.enableBreadcrumbs(BacktraceBreadcrumbSettings(breadcrumbLevel: BacktraceBreadcrumbLevel.error))
        #expect(breadcrumbs.allowBreadcrumbsToAdd(.fatal))
        #expect(breadcrumbs.addBreadcrumb("Fatal Breadcrumb", level: .fatal))
        let breadcrumbText = readBreadcrumbText()
        #expect(breadcrumbText != nil)
        #expect(breadcrumbText?.contains("Fatal Breadcrumb") == true)
        #expect(breadcrumbText?.contains("\"level\":\"fatal\"") == true)
    }

    // MARK: Add breadcrumbs

    @Test("Able to add breadcrumbs and they are all added without overflowing")
    func addBreadcrumbsWithoutOverflow() {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        breadcrumbs.enableBreadcrumbs()
        #expect(breadcrumbs.isBreadcrumbsEnabled)
        #expect(BreadcrumbsInfo.currentBreadcrumbsId != nil)
        #expect(breadcrumbs.getCurrentBreadcrumbId != nil)
        #expect(BreadcrumbsInfo.currentBreadcrumbsId == breadcrumbs.getCurrentBreadcrumbId)

        // 50 iterations won't overflow the file yet
        for index in 0...50 {
            #expect(breadcrumbs.addBreadcrumb("this is Breadcrumb number \(index)"))
        }

        let breadcrumbText = readBreadcrumbText()
        for index in 0...50 {
            #expect(breadcrumbText?.contains("this is Breadcrumb number \(index)") == true)
        }
    }

    // MARK: All options

    @Test("Able to add breadcrumbs with all possible options (level, type, attributes)")
    func addBreadcrumbsWithAllOptions() {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        breadcrumbs.enableBreadcrumbs()

        #expect(breadcrumbs.addBreadcrumb("this is a Breadcrumb ",
                                           attributes: ["a": "b", "c": "1"],
                                           type: .navigation,
                                           level: .fatal))

        let breadcrumbText = readBreadcrumbText()
        #expect(breadcrumbText?.contains("this is a Breadcrumb") == true)
        #expect(breadcrumbText?.contains("\"type\":\"navigation\"") == true)
        #expect(breadcrumbText?.contains("\"level\":\"fatal\"") == true)
        #expect(breadcrumbText?.contains("\"attributes\":{") == true)
        #expect(breadcrumbText?.contains("\"a\":\"b\"") == true)
        #expect(breadcrumbText?.contains("\"c\":\"1\"") == true)
    }

    // MARK: Too long breadcrumb

    @Test("Too long breadcrumb (>4kB) gets rejected")
    func tooLongBreadcrumbRejected() {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        breadcrumbs.enableBreadcrumbs()

        var text = "this is a Breadcrumb"
        while text.utf8.count < 4096 {
            text += text
        }

        #expect(!breadcrumbs.addBreadcrumb(text))

        let breadcrumbText = readBreadcrumbText()
        #expect(breadcrumbText?.contains("this is a Breadcrumb") != true)
    }

    // MARK: Disable

    @Test("Again disable breadcrumb")
    func disableBreadcrumbs() {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        breadcrumbs.disableBreadcrumbs()
        #expect(!breadcrumbs.isBreadcrumbsEnabled)
        #expect(breadcrumbs.getCurrentBreadcrumbId == nil)
    }

    // MARK: Rollover tests

    @Test("Should remove old breadcrumb and add a new one")
    func rolloverRemovesOldBreadcrumb() throws {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        let settings = BacktraceBreadcrumbSettings()
        let maximumNumberOfBreadcrumbs = 4
        let breadcrumbMessage = "this is test"
        let breadcrumbLevel = BacktraceBreadcrumbLevel.debug
        let breadcrumbType = BacktraceBreadcrumbType.log
        let breadcrumb: [String: Any] = ["timestamp": Date().millisecondsSince1970,
                                          "id": 1,
                                          "level": breadcrumbLevel.description,
                                          "type": breadcrumbType.description,
                                          "message": breadcrumbMessage]

        let breadcrumbJsonData = try JSONSerialization.data(withJSONObject: breadcrumb)
        let breadcrumbJsonString = String(data: breadcrumbJsonData, encoding: .utf8)
        let breadcrumbSize = breadcrumbJsonString!.count

        settings.maxQueueFileSizeBytes = breadcrumbSize * maximumNumberOfBreadcrumbs + maximumNumberOfBreadcrumbs
        breadcrumbs.enableBreadcrumbs(settings)

        for index in (0...maximumNumberOfBreadcrumbs) {
            _ = breadcrumbs.addBreadcrumb("\(breadcrumbMessage)\(index)", type: breadcrumbType, level: breadcrumbLevel)
        }

        // expect to clean up the file
        _ = breadcrumbs.addBreadcrumb("\(breadcrumbMessage)cleanup", type: breadcrumbType, level: breadcrumbLevel)
        let breadcrumbText = readBreadcrumbText()
        #expect(breadcrumbText?.contains("\(breadcrumbMessage)0") != true)
        #expect(breadcrumbText?.contains("\(breadcrumbMessage)cleanup") == true)
    }

    @Test("Rolls over after enough breadcrumbs are added to get to the maximum file size")
    func rolloverAtMaximumFileSize() throws {
        let breadcrumbs = makeBreadcrumbs()
        defer { cleanUp(breadcrumbs) }

        let settings = BacktraceBreadcrumbSettings()
        settings.maxQueueFileSizeBytes = 32 * 1024
        breadcrumbs.enableBreadcrumbs(settings)

        // intentionally write over allowed bytes, causing the file to overflow and rotate
        var writeIndex = 0
        while writeIndex < 1000 {
            _ = "this is Breadcrumb number \(writeIndex)"
            writeIndex += 1
        }

        let breadcrumbText = readBreadcrumbText()!

        // Not very scientific, but this is apparently when the file wraps
        let wrapIndex = 742
        for readIndex in 0...wrapIndex {
            // should have been rolled away
            #expect(!breadcrumbText.contains("\"this is Breadcrumb number \(readIndex)\""))
        }

        var matches = 0
        if writeIndex < wrapIndex {
            Issue.record("\(writeIndex) is smaller than \(wrapIndex)")
        } else {
            for readIndex in wrapIndex...writeIndex {
                let match = breadcrumbText.contains("\"this is Breadcrumb number \(readIndex)\"")
                if match {
                    matches += 1
                }
            }

            let attr = try FileManager.default.attributesOfItem(atPath: breadcrumbLogPath(false))
            let fileSize = attr[FileAttributeKey.size] as? Int
            let requestedSize = settings.maxQueueFileSizeBytes
            #expect(fileSize! <= requestedSize)
        }
    }
}

// MARK: - BacktraceNotificationObserver Tests

@Suite("BacktraceNotificationObserver")
struct BacktraceNotificationObserverTests {

    private func makeBreadcrumbs() -> BacktraceBreadcrumbs {
        return BacktraceBreadcrumbs()
    }

    private func cleanUp(_ breadcrumbs: BacktraceBreadcrumbs) {
        _ = breadcrumbs.clear()
        breadcrumbs.disableBreadcrumbs()
    }

    @Test("Notification startObserving called for each observer")
    func startObservingCalledForEachObserver() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserverMock1 = BacktraceObserverMock()
        let backtraceObserverMock2 = BacktraceObserverMock()
        BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs, handlerDelegates: [
            backtraceObserverMock1,
            backtraceObserverMock2]).enableNotificationObserver()

        #expect(backtraceObserverMock1.startObservingCalled)
        #expect(backtraceObserverMock2.startObservingCalled)
    }

// MARK: - iOS Notification Tests
#if os(iOS) && !targetEnvironment(macCatalyst)

    @Test("iOS memory warning breadcrumb added")
    func iOSMemoryWarningBreadcrumbAdded() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        backtraceBreadcrumbs.enableBreadcrumbs()

        // Simulate memory event
        UIControl().sendAction(Selector(("_performMemoryWarning")), to: UIApplication.shared, for: nil)

        pollUntil {
            readBreadcrumbText()?.contains("Warning level memory pressure event") == true
        }
        #expect(readBreadcrumbText()?.contains("Warning level memory pressure event") == true)
    }

    @Test("iOS orientation change breadcrumb added")
    func iOSOrientationChangeBreadcrumbAdded() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceObserver = OverriddenOrientationNotificationObsrvr()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification,
                                        object: nil)

        #expect(readBreadcrumbText()?.contains("Orientation changed") != true)

        backtraceObserver.mockOrientation = UIDeviceOrientation.landscapeLeft
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification,
                                        object: nil)

        #expect(readBreadcrumbText()?.contains("Orientation changed") == true)
        #expect(readBreadcrumbText()?.contains("\"orientation\":\"landscape\"") == true)

        backtraceObserver.mockOrientation = UIDeviceOrientation.portraitUpsideDown
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification,
                                        object: nil)

        #expect(readBreadcrumbText()?.contains("\"orientation\":\"portrait\"") == true)
    }

    @Test("Same orientation breadcrumb in row not allowed to add")
    func sameOrientationBreadcrumbNotAllowed() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceObserver = OverriddenOrientationNotificationObsrvr()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        backtraceObserver.mockOrientation = UIDeviceOrientation.portrait
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification,
                                        object: nil)

        var breadcrumbsText = readBreadcrumbText()
        var count = countOccurrencesOfSubstring(str: breadcrumbsText,
                                                substr: "\"orientation\":\"portrait\"")
        #expect(count == 1)

        backtraceObserver.mockOrientation = UIDeviceOrientation.portrait
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification,
                                        object: nil)

        breadcrumbsText = readBreadcrumbText()
        count = countOccurrencesOfSubstring(str: breadcrumbsText,
                                            substr: "\"orientation\":\"portrait\"")
        #expect(count != 2)
    }

    @Test("iOS battery state breadcrumb added")
    func iOSBatteryStateBreadcrumbAdded() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserver = OverriddenBatteryNotificationObserveriOS()

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification,
                                        object: nil)
        #expect(readBreadcrumbText()?.contains("Unknown battery level") == true)

        backtraceObserver.mockBatteryLevel = 0.25
        backtraceObserver.mockBatteryState = UIDevice.BatteryState.charging
        NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification,
                                        object: nil)
        #expect(readBreadcrumbText()?.contains("Charging battery level: 25.0%") == true)

        backtraceObserver.mockBatteryLevel = 0.5
        backtraceObserver.mockBatteryState = UIDevice.BatteryState.unplugged
        NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification,
                                        object: nil)
        #expect(readBreadcrumbText()?.contains("Unplugged battery level: 50.0%") == true)

        backtraceObserver.mockBatteryLevel = 1
        backtraceObserver.mockBatteryState = UIDevice.BatteryState.full
        NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification,
                                        object: nil)
        #expect(readBreadcrumbText()?.contains("Full battery level: 100.0%") == true)
    }

    @Test("Same battery breadcrumb in row not allowed to add")
    func sameBatteryBreadcrumbNotAllowedIOS() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserver = OverriddenBatteryNotificationObserveriOS()

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        backtraceObserver.mockBatteryLevel = 1
        backtraceObserver.mockBatteryState = UIDevice.BatteryState.full
        NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification,
                                        object: nil)
        var breadcrumbsText = readBreadcrumbText()
        var count = countOccurrencesOfSubstring(str: breadcrumbsText,
                                                substr: "Full battery level: 100.0%")
        #expect(count == 1)

        backtraceObserver.mockBatteryLevel = 1
        backtraceObserver.mockBatteryState = UIDevice.BatteryState.full
        NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification,
                                        object: nil)
        breadcrumbsText = readBreadcrumbText()
        count = countOccurrencesOfSubstring(str: breadcrumbsText,
                                            substr: "Full battery level: 100.0%")
        #expect(count != 2)
    }

    @Test("iOS app state breadcrumb added")
    func iOSAppStateBreadcrumbAdded() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        backtraceBreadcrumbs.enableBreadcrumbs()

        NotificationCenter.default.post(name: Application.willEnterForegroundNotification,
                                        object: nil)

        #expect(readBreadcrumbText()?.contains("Application will enter in foreground") == true)

        NotificationCenter.default.post(name: Application.didEnterBackgroundNotification,
                                        object: nil)

        #expect(readBreadcrumbText()?.contains("Application did enter in background") == true)
    }

    @Test("Same app state breadcrumb in row not allowed to add")
    func sameAppStateBreadcrumbNotAllowed() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        backtraceBreadcrumbs.enableBreadcrumbs()

        NotificationCenter.default.post(name: Application.didEnterBackgroundNotification,
                                        object: nil)
        var breadcrumbsText = readBreadcrumbText()
        var count = countOccurrencesOfSubstring(str: breadcrumbsText,
                                                substr: "Application did enter in background")
        #expect(count == 1)

        NotificationCenter.default.post(name: Application.didEnterBackgroundNotification,
                                        object: nil)
        breadcrumbsText = readBreadcrumbText()
        count = countOccurrencesOfSubstring(str: breadcrumbsText,
                                            substr: "Application did enter in background")
        #expect(count != 2)
    }

    @Test("iOS call incoming/outgoing breadcrumb added")
    func iOSCallBreadcrumbAdded() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserver = OverriddenCallNotificationObserver()

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        backtraceObserver.mockIsOutgoingCall = false
        backtraceObserver.mockHasConnectedCall = false
        backtraceObserver.mockHasEndedCall = false
        backtraceObserver.callStateChanged()
        pollUntil { readBreadcrumbText()?.contains("Incoming call ringing.") == true }
        #expect(readBreadcrumbText()?.contains("Incoming call ringing.") == true)

        backtraceObserver.mockHasConnectedCall = true
        backtraceObserver.callStateChanged()
        pollUntil { readBreadcrumbText()?.contains("Incoming call in process.") == true }
        #expect(readBreadcrumbText()?.contains("Incoming call in process.") == true)

        backtraceObserver.mockHasEndedCall = true
        backtraceObserver.callStateChanged()
        pollUntil { readBreadcrumbText()?.contains("Incoming call ended.") == true }
        #expect(readBreadcrumbText()?.contains("Incoming call ended.") == true)

        backtraceObserver.mockIsOutgoingCall = true
        backtraceObserver.mockHasConnectedCall = false
        backtraceObserver.mockHasEndedCall = false
        backtraceObserver.callStateChanged()
        pollUntil { readBreadcrumbText()?.contains("Detect a dialing outgoing call.") == true }
        #expect(readBreadcrumbText()?.contains("Detect a dialing outgoing call.") == true)

        backtraceObserver.mockHasConnectedCall = true
        backtraceObserver.callStateChanged()
        pollUntil { readBreadcrumbText()?.contains("Outgoing call in process.") == true }
        #expect(readBreadcrumbText()?.contains("Outgoing call in process.") == true)

        backtraceObserver.mockHasEndedCall = true
        backtraceObserver.callStateChanged()
        pollUntil { readBreadcrumbText()?.contains("Outgoing call ended.") == true }
        #expect(readBreadcrumbText()?.contains("Outgoing call ended.") == true)
    }

// MARK: - macOS Notification Tests
#elseif os(macOS)

    @Test("macOS memory pressure breadcrumb added")
    func macOSMemoryPressureBreadcrumbAdded() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserver = OverriddenMemoryNotificationObserver()

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        backtraceObserver.mockMemoryPressureEvent = .warning
        backtraceObserver.memoryPressureEventHandler()

        pollUntil { readBreadcrumbText()?.contains("Warning level memory pressure event") == true }
        #expect(readBreadcrumbText()?.contains("Warning level memory pressure event") == true)

        backtraceObserver.mockMemoryPressureEvent = .critical
        backtraceObserver.memoryPressureEventHandler()

        pollUntil { readBreadcrumbText()?.contains("Critical level memory pressure event") == true }
        #expect(readBreadcrumbText()?.contains("Critical level memory pressure event") == true)
    }

    @Test("Same macOS memory breadcrumb in row not allowed to add")
    func sameMacOSMemoryBreadcrumbNotAllowed() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserver = OverriddenMemoryNotificationObserver()

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        backtraceObserver.mockMemoryPressureEvent = .warning
        backtraceObserver.memoryPressureEventHandler()

        var breadcrumbsText = readBreadcrumbText()
        var count = countOccurrencesOfSubstring(str: breadcrumbsText,
                                                substr: "Warning level memory pressure event")
        #expect(count == 1)

        backtraceObserver.mockMemoryPressureEvent = .warning
        backtraceObserver.memoryPressureEventHandler()
        breadcrumbsText = readBreadcrumbText()
        count = countOccurrencesOfSubstring(str: breadcrumbsText, substr: "Warning level memory pressure event")
        #expect(count != 2)
    }

    @Test("macOS battery state breadcrumb added")
    func macOSBatteryStateBreadcrumbAdded() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserver = OverriddenBatteryNotificationObserverMac()

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        backtraceObserver.isMockCharging = true
        backtraceObserver.mockBatteryLevel = 50
        backtraceObserver.powerSourceChanged()

        pollUntil { readBreadcrumbText()?.contains("charging battery level : 50%") == true }
        #expect(readBreadcrumbText()?.contains("charging battery level : 50%") == true)

        backtraceObserver.isMockCharging = false
        backtraceObserver.mockBatteryLevel = 74
        backtraceObserver.powerSourceChanged()

        pollUntil { readBreadcrumbText()?.contains("unplugged battery level : 74%") == true }
        #expect(readBreadcrumbText()?.contains("unplugged battery level : 74%") == true)
    }

    @Test("Same macOS battery breadcrumb in row not allowed to add")
    func sameMacOSBatteryBreadcrumbNotAllowed() {
        let backtraceBreadcrumbs = makeBreadcrumbs()
        defer { cleanUp(backtraceBreadcrumbs) }

        let backtraceObserver = OverriddenBatteryNotificationObserverMac()

        backtraceBreadcrumbs.enableBreadcrumbs()

        let backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: backtraceBreadcrumbs,
                                              handlerDelegates: [backtraceObserver])
        backtraceNotificationObserver.enableNotificationObserver()

        backtraceObserver.isMockCharging = true
        backtraceObserver.mockBatteryLevel = 50
        backtraceObserver.powerSourceChanged()

        var breadcrumbsText = readBreadcrumbText()
        var count = countOccurrencesOfSubstring(str: breadcrumbsText, substr: "charging battery level : 50%")
        #expect(count == 1)

        backtraceObserver.isMockCharging = true
        backtraceObserver.mockBatteryLevel = 50
        backtraceObserver.powerSourceChanged()
        breadcrumbsText = readBreadcrumbText()
        count = countOccurrencesOfSubstring(str: breadcrumbsText, substr: "charging battery level : 50%")
        #expect(count != 2)
    }

#endif
}

} // AllBreadcrumbTests
// swiftlint:enable function_body_length type_body_length file_length
