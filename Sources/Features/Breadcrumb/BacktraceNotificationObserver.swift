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
    
    init(breadcrumbs: BacktraceBreadcrumbs,
         handlerDelegates: [BacktraceNotificationHandlerDelegate] =  [
            BacktraceOrientationNotificationObserver(),
            BacktraceMemoryNotificationObserver(),
            BacktraceBatteryNotificationObserver()]) {
        self.breadcrumbs = breadcrumbs
        self.handlerDelegates = handlerDelegates
        super.init()
        self.enableNotificationObserver()
    }

    func enableNotificationObserver() {
        handlerDelegates?.forEach({ $0.startObserving(self) })
    }
    
    deinit {
        self.handlerDelegates = nil
    }
    
    func addBreadcrumb(_ message: String, attributes: [String : String]?, type: BacktraceBreadcrumbType, level: BacktraceBreadcrumbLevel) {
        let result = breadcrumbs.addBreadcrumb(message,
                                      attributes: attributes,
                                      type: .system,
                                      level: .info)
        print(result)
    }
}

protocol BacktraceNotificationHandlerDelegate: class {
    
    var delegate: BacktraceNotificationObserverDelegate? { get set }
    
    func startObserving(_ delegate: BacktraceNotificationObserverDelegate)
}

// MARK: - Orientation Status Listener
class BacktraceOrientationNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {
        
    weak var delegate: BacktraceNotificationObserverDelegate?
        
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        observeOrientationChange()
    }

    private func observeOrientationChange() {
#if os(iOS)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyOrientationChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
#endif
    }
#if os(iOS)
    @objc private func notifyOrientationChange() {
        switch UIDevice.current.orientation {
        case .portrait, .portraitUpsideDown:
            addOrientationBreadcrumb("portrait")
        case .landscapeLeft, .landscapeRight:
            addOrientationBreadcrumb("landscape")
        default:
            print("unknown")
        }
    }

    private func addOrientationBreadcrumb(_ orientation: String) {
        let attributes = ["orientation": orientation]
        _ = delegate?.addBreadcrumb("Orientation changed",
                                    attributes: attributes,
                                    type: .system,
                                    level: .info)
    }
#endif

}

// MARK: Memory Status Listener
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
                    self.delegate?.addBreadcrumb(message,
                                                 attributes: nil,
                                                 type: .system,
                                                 level: level)
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

// MARK: - Battery Status Listener
class BacktraceBatteryNotificationObserver: NSObject, BacktraceNotificationHandlerDelegate {
    
    var delegate: BacktraceNotificationObserverDelegate?
    
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
            self.delegate?.addBreadcrumb(message,
                                         attributes: nil,
                                         type: .system,
                                         level: .info)
        }
    }
    
#elseif os(iOS)
    
    func startObserving(_ delegate: BacktraceNotificationObserverDelegate) {
        self.delegate = delegate
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyBatteryStatusChange),
                                               name: UIDevice.batteryLevelDidChangeNotification,
                                               object: nil)
    }
    private func getBatteryWarningText() -> String {
        let batteryLevel = UIDevice.current.batteryLevel
        switch UIDevice.current.batteryState {
        case .unknown:
            return "Unknown battery level : \(batteryLevel * 100)%"
        case .unplugged:
            return "unplugged battery level : \(batteryLevel * 100)%"
        case .charging:
            return "charging battery level : \(batteryLevel * 100)%"
        case .full:
            return "full battery level : \(batteryLevel * 100)%"
        }
    }

    @objc private func notifyBatteryStatusChange() {
        delegate?.addBreadcrumb(getBatteryWarningText(),
                                attributes: nil,
                                type: .system,
                                level: .info)
    }
#endif
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
