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

    private var handlerDelegates: [BacktraceNotificationHandlerDelegate]?

    init(breadcrumbs: BacktraceBreadcrumbs) {
        self.breadcrumbs = breadcrumbs
        self.handlerDelegates = [
            BacktraceMemoryNotificationObserver(),
            BacktraceBatteryNotificationObserver()]
#if os(iOS)
        self.handlerDelegates?.append(BacktraceOrientationNotificationObserver())
        self.handlerDelegates?.append(BacktraceAppStateNotificationObserver())
#endif
        super.init()
    }

    init(breadcrumbs: BacktraceBreadcrumbs,
         handlerDelegates: [BacktraceNotificationHandlerDelegate]) {
        self.breadcrumbs = breadcrumbs
        self.handlerDelegates = handlerDelegates
        super.init()
    }

    func enableNotificationObserver() {
        handlerDelegates?.forEach({ $0.startObserving(self) })
    }

    deinit {
        self.handlerDelegates = nil
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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

}
#endif

// MARK: Memory Status Observer
class BacktraceMemoryNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

    private var source: DispatchSourceMemoryPressure?

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        if let source: DispatchSourceMemoryPressure =
            DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: DispatchQueue.main) as? DispatchSource {
            let eventHandler: DispatchSourceProtocol.DispatchSourceHandler = {
                let event: DispatchSource.MemoryPressureEvent = source.data
                if source.isCancelled == false {
                    let message = self.getMemoryWarningText(event)
                    let level = self.getMemoryWarningLevel(event)
                    self.addBreadcrumb(message, level: level)
                }
            }
            source.setEventHandler(handler: eventHandler)
            source.setRegistrationHandler(handler: eventHandler)
            if #available(iOS 11.0, macOS 10.12, *) {
                source.activate()
            } else {
                source.resume()
            }
            self.source = source
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
    }
}

// MARK: - Battery Status Observer
class BacktraceBatteryNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {

    weak var delegate: BacktraceNotificationObserverDelegate?

    func addBreadcrumb(_ message: String) {
        delegate?.addBreadcrumb(message,
                                attributes: nil,
                                type: .system,
                                level: .info)
    }
    
#if os(OSX)
    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]
        if let psPowerSource = psList.first,
           let psDesc = IOPSGetPowerSourceDescription(psInfo, psPowerSource).takeUnretainedValue() as? [String: Any],
           let isCharging = (psDesc[kIOPSIsChargingKey] as? Bool),
           let batteryLevel = psDesc[kIOPSCurrentCapacityKey] {
            let message: String
            if isCharging {
                message = "charging battery level : \(batteryLevel)%"
            } else {
                message = "unplugged battery level : \(batteryLevel)%"
            }
            self.addBreadcrumb(message)
        }
    }

#elseif os(iOS)
    var batteryState: UIDevice.BatteryState { UIDevice.current.batteryState }
    var batteryLevel: Float { UIDevice.current.batteryLevel }

    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        UIDevice.current.isBatteryMonitoringEnabled = true
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
}
#endif
