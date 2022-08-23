import Foundation
#if os(OSX)
import IOKit.ps
#endif

protocol BacktraceNotificationObserverDelegate: class {

    func addBreadcrumb(_ message: String,
                       attributes: [String: String]?,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel)
}

@objc class BacktraceNotificationObserver: NSObject, BacktraceNotificationObserverDelegate {

    private let breadcrumbs: BacktraceBreadcrumbs

    private let handlerDelegates: [BacktraceNotificationHandlerDelegate]

    init(breadcrumbs: BacktraceBreadcrumbs) {
        self.breadcrumbs = breadcrumbs
        var handlerDelegates: [BacktraceNotificationHandlerDelegate] = [
            BacktraceMemoryNotificationObserver(),
            BacktraceBatteryNotificationObserver()]
#if os(iOS)
        handlerDelegates.append(BacktraceOrientationNotificationObserver())
        handlerDelegates.append(BacktraceAppStateNotificationObserver())
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

    func addBreadcrumb(_ message: String, attributes: [String: String]?,
                       type: BacktraceBreadcrumbType,
                       level: BacktraceBreadcrumbLevel) {
        _ = breadcrumbs.addBreadcrumb(message,
                                      attributes: attributes,
                                      type: .system,
                                      level: .info)
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

    var orientation: UIDeviceOrientation { UIDevice.current.orientation }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyOrientationChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
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
        let attributes = ["orientation": orientation]
        _ = delegate?.addBreadcrumb("Orientation changed",
                                    attributes: attributes,
                                    type: .system,
                                    level: .info)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
#endif

// MARK: Memory Status Observer
class BacktraceMemoryNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

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
#if os(iOS)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveMemoryWarningNotification),
                                               name: Application.didReceiveMemoryWarningNotification,
                                               object: nil)
#endif
    }
    
    @objc private func didReceiveMemoryWarningNotification() {
        if let event = self.memoryPressureEvent, self.source?.isCancelled == false {
            let message = self.getMemoryWarningText(event)
            let level = self.getMemoryWarningLevel(event)
            addBreadcrumb(message, level: level)
        } else {
            addBreadcrumb("Test memory warning", level: .debug)
        }
    }

    func addBreadcrumb(_ message: String, level: BacktraceBreadcrumbLevel) {
        self.delegate?.addBreadcrumb(message,
                                     attributes: nil,
                                     type: .system,
                                     level: level)
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
#if os(iOS)
        NotificationCenter.default.removeObserver(self)
#endif
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

class BacktraceBatteryNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

    func addBreadcrumb(_ message: String) {
        delegate?.addBreadcrumb(message,
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

    func powerSourceChanged() {
        if let isCharging = isCharging, let batteryLevel = batteryLevel {
            var message = ""
            if isCharging {
                message = "charging battery level : \(batteryLevel)%"
            } else {
                message = "unplugged battery level : \(batteryLevel)%"
            }
            self.addBreadcrumb(message)
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
        addBreadcrumb(getBatteryWarningText())
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
#endif
}

#if os(iOS)
// MARK: - Application State Observer
class BacktraceAppStateNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    var delegate: BacktraceNotificationObserverDelegate?

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        observeApplicationStateChange()
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
        addApplicationStateBreadcrumb("Application will enter in foreground")
    }

    @objc private func didEnterBackgroundNotification() {
        addApplicationStateBreadcrumb("Application did enter in background")
    }

    private func addApplicationStateBreadcrumb(_ message: String) {
        _ = delegate?.addBreadcrumb(message,
                                    attributes: nil,
                                    type: .system,
                                    level: .info)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
#endif
