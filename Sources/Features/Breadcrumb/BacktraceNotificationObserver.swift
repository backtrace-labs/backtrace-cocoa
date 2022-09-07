import Foundation
#if os(OSX)
import IOKit.ps
#endif

protocol BacktraceNotificationObserverDelegate: class {

    func addBreadcrumb(_ message: String,
                       attributes: [String: String]?,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel) -> Bool
}

@objc class BacktraceNotificationObserver: NSObject, BacktraceNotificationObserverDelegate {

    private let breadcrumbs: BacktraceBreadcrumbs

    private let handlerDelegates: [BacktraceNotificationHandlerDelegate]

    init(breadcrumbs: BacktraceBreadcrumbs) {
        self.breadcrumbs = breadcrumbs
        var handlerDelegates: [BacktraceNotificationHandlerDelegate] = [
            BacktraceMemoryNotificationObserver()]
#if os(iOS)
        handlerDelegates.append(contentsOf: [
            BacktraceBatteryNotificationObserver(),
            BacktraceOrientationNotificationObserver(),
            BacktraceAppStateNotificationObserver()
        ])
#elseif os(OSX)
        handlerDelegates.append(BacktraceBatteryNotificationObserver())
#endif
        self.handlerDelegates = handlerDelegates
        super.init()
    }

    init(breadcrumbs: BacktraceBreadcrumbs,
         handlerDelegates: [BacktraceNotificationHandlerDelegate]) {
        self.breadcrumbs = breadcrumbs
        self.handlerDelegates = handlerDelegates
        super.init()
    }

    func enableNotificationObserver() {
        handlerDelegates.forEach({ $0.startObserving(self) })
    }

    func addBreadcrumb(_ message: String,
                       attributes: [String: String]?,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel) -> Bool {
        return breadcrumbs.addBreadcrumb(message,
                                         attributes: attributes,
                                         type: type,
                                         level: level)
    }
}

protocol BacktraceNotificationHandlerDelegate: class {

    var delegate: BacktraceNotificationObserverDelegate? { get set }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate)
}

#if os(iOS)
// MARK: - Orientation Status Listener
class BacktraceOrientationNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

    var lastOrientation: UIDeviceOrientation?

    var orientation: UIDeviceOrientation { UIDevice.current.orientation }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyOrientationChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }

    func isDirty() -> Bool {
        if let lastOrientation = lastOrientation {
            return lastOrientation != orientation
        }
        return true
    }

    @objc private func notifyOrientationChange() {
        switch orientation {
        case .portrait, .portraitUpsideDown:
            addOrientationBreadcrumb("portrait")
        case .landscapeLeft, .landscapeRight:
            addOrientationBreadcrumb("landscape")
        default:
            BacktraceLogger.warning("Unknown orientation type: \(orientation)")
        }
    }

    private func addOrientationBreadcrumb(_ orientation: String) {
        if isDirty() {
            let attributes = ["orientation": orientation]
            if let result = delegate?.addBreadcrumb("Orientation changed",
                                                    attributes: attributes,
                                                    type: .system,
                                                    level: .info),
               result {
                lastOrientation = self.orientation
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
#endif

// MARK: Memory Status Observer
class BacktraceMemoryNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

    var lastMemoryPressureEvent: DispatchSource.MemoryPressureEvent?

    private var source: DispatchSourceMemoryPressure?

    var memoryPressureEvent: DispatchSource.MemoryPressureEvent? {
        return source?.data
    }

    lazy var memoryPressureEventHandler: DispatchSourceProtocol.DispatchSourceHandler = { [weak self] in
        guard let self = self else { return }
        if let event = self.memoryPressureEvent, self.source?.isCancelled == false {
            let message = self.getMemoryWarningText(event)
            let level = self.getMemoryWarningLevel(event)
            self.addBreadcrumb(message, level: level)
        }
    }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        if let source: DispatchSourceMemoryPressure =
            DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: DispatchQueue.main) as? DispatchSource {
            self.source = source
            source.setEventHandler(handler: memoryPressureEventHandler)
            source.setRegistrationHandler(handler: memoryPressureEventHandler)
            if #available(iOS 11.0, macOS 10.12, *) {
                source.activate()
            } else {
                source.resume()
            }
        }
    }

    func isDirty() -> Bool {
        if let lastMemoryPressureEvent = lastMemoryPressureEvent {
            return lastMemoryPressureEvent.rawValue != memoryPressureEvent?.rawValue
         }
         return true
    }

    func addBreadcrumb(_ message: String, level: BacktraceBreadcrumbLevel) {
        if isDirty() {
            if let result = delegate?.addBreadcrumb(message,
                                                    attributes: nil,
                                                    type: .system,
                                                    level: level),
               result {
                lastMemoryPressureEvent = memoryPressureEvent
            }
        }
    }

    private func getMemoryWarningText(_ memoryPressureEvent: DispatchSource.MemoryPressureEvent) -> String {
        if memoryPressureEvent.rawValue == DispatchSource.MemoryPressureEvent.normal.rawValue {
            return "Normal level memory pressure event"
        } else if memoryPressureEvent.rawValue == DispatchSource.MemoryPressureEvent.critical.rawValue {
            return "Critical level memory pressure event"
        } else if memoryPressureEvent.rawValue == DispatchSource.MemoryPressureEvent.warning.rawValue {
            return "Warning level memory pressure event"
        } else {
            return "Unspecified level memory pressure event"
        }
    }

    private func getMemoryWarningLevel(_ memoryPressureEvent: DispatchSource.MemoryPressureEvent) -> BacktraceBreadcrumbLevel {
        if memoryPressureEvent.rawValue == DispatchSource.MemoryPressureEvent.normal.rawValue {
            return .warning
        } else if memoryPressureEvent.rawValue == DispatchSource.MemoryPressureEvent.critical.rawValue {
            return .fatal
        } else if memoryPressureEvent.rawValue == DispatchSource.MemoryPressureEvent.warning.rawValue {
            return .error
        } else {
            return .debug
        }
    }

    deinit {
        self.source?.cancel()
        self.source = nil
    }
}

// MARK: - Battery Status Observer
#if os(OSX)
func powerSourceObserver(context: UnsafeMutableRawPointer?) {
    if let context = context {
        let opaque = Unmanaged<BacktraceBatteryNotificationObserver>.fromOpaque(context)
        let unretainSelf = opaque.takeUnretainedValue()
        unretainSelf.powerSourceChanged()
    }
}
#endif

#if os(iOS) || os(OSX)
class BacktraceBatteryNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

    func addBreadcrumb(_ message: String) -> Bool? {
        return delegate?.addBreadcrumb(message,
                                       attributes: nil,
                                       type: .system,
                                       level: .info)
    }

#if os(OSX)
    var loop: CFRunLoopSource?

    private var powerSourceInfo: [String: Any]? {
        let psInfo = IOPSCopyPowerSourcesInfo().takeUnretainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeUnretainedValue() as [CFTypeRef]
        if let psPowerSource = psList.first {
            return IOPSGetPowerSourceDescription(psInfo, psPowerSource).takeUnretainedValue() as? [String: Any]
        } else {
            return nil
        }
    }

    var lastCharging: Bool?

    var isCharging: Bool? {
        powerSourceInfo?[kIOPSIsChargingKey] as? Bool
    }

    var batteryLevel: Int? {
        powerSourceInfo?[kIOPSCurrentCapacityKey] as? Int
    }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        stopLoopSourceIfExist()
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        let context = UnsafeMutableRawPointer(opaque)
        loop = IOPSNotificationCreateRunLoopSource(
            powerSourceObserver,
                context
        ).takeRetainedValue() as CFRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.commonModes)
    }

    func isDirty() -> Bool {
        if let lastCharging = lastCharging {
            return lastCharging != isCharging
        }
        return true
    }

    func powerSourceChanged() {
        if let isCharging = isCharging, let batteryLevel = batteryLevel, isDirty() {
            let message = isCharging ? "charging battery level : \(batteryLevel)%"
            : "unplugged battery level : \(batteryLevel)%"
            if let result = addBreadcrumb(message), result {
                lastCharging = isCharging
            }
        }
    }

    func stopLoopSourceIfExist() {
        if let loop = loop, CFRunLoopContainsSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.commonModes) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.commonModes)
        }
    }

    deinit {
        stopLoopSourceIfExist()
    }
#elseif os(iOS)
    var lastBatteryState: UIDevice.BatteryState?

    var batteryState: UIDevice.BatteryState { UIDevice.current.batteryState }
    var batteryLevel: Float { UIDevice.current.batteryLevel }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyBatteryStatusChange),
                                               name: UIDevice.batteryStateDidChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyBatteryStatusChange),
                                               name: UIDevice.batteryLevelDidChangeNotification,
                                               object: nil)
    }

    func isDirty() -> Bool {
        if let lastBatteryState = lastBatteryState {
            return lastBatteryState != batteryState
        }
        return true
    }

    private func getBatteryWarningText() -> String {
        switch batteryState {
        case .unknown:
            return "Unknown battery level"
        case .unplugged:
            return "Unplugged battery level: \(batteryLevel * 100)%"
        case .charging:
            return "Charging battery level: \(batteryLevel * 100)%"
        case .full:
            return "Full battery level: \(batteryLevel * 100)%"
        }
    }

    @objc private func notifyBatteryStatusChange() {
        if isDirty() {
            if let result = addBreadcrumb(getBatteryWarningText()), result {
                lastBatteryState = batteryState
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
#endif
}
#endif

#if os(iOS)
// MARK: - Application State Observer
enum ApplicationState: Int {
    case willEnterForeground
    case didEnterBackground
}

class BacktraceAppStateNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

    var lastAppState: ApplicationState?
    var appState: ApplicationState? {
        didSet {
            self.addApplicationStateBreadcrumb()
        }
    }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        observeApplicationStateChange()
    }

    func isDirty() -> Bool {
        if let lastAppState = lastAppState {
            return lastAppState != appState
        }
        return true
    }

    private func observeApplicationStateChange() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: Application.willEnterForegroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackgroundNotification),
                                               name: Application.didEnterBackgroundNotification,
                                               object: nil)
    }

    @objc private func applicationWillEnterForeground() {
        appState = .willEnterForeground
    }

    @objc private func didEnterBackgroundNotification() {
        appState = .didEnterBackground
    }

    private func addApplicationStateBreadcrumb() {
        if let appState = appState, isDirty() {
            let message = (appState == .willEnterForeground) ? "Application will enter in foreground"
            : "Application did enter in background"
            if let result = delegate?.addBreadcrumb(message,
                                                    attributes: nil,
                                                    type: .system,
                                                    level: .info),
            result {
                lastAppState = appState
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
#endif
