import Foundation
#if os(OSX)
import IOKit.ps
#endif

@objc class BacktraceNotificationObserver: NSObject {

    private let breadcrumbs: BacktraceBreadcrumbs
    init(breadcrumbs: BacktraceBreadcrumbs) {
        self.breadcrumbs = breadcrumbs
        super.init()
#if os(iOS)
        observeOrientationChange()
        observeBatteryStatusChanged()
#elseif os(OSX)
        addCurrentBatteryPercentage()
#endif
        observeMemoryStatusChanged()
    }

    deinit {
#if os(iOS)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
#endif
        self.source?.cancel()
    }

#if os(OSX)
    private func addCurrentBatteryPercentage() {
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

            _ = breadcrumbs.addBreadcrumb(message,
                                                  type: .system,
                                                  level: .info)
        }
    }
#endif

    // MARK: - Orientation Status Listener
#if os(iOS)
    private func observeOrientationChange() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyOrientationChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }

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
        _ = breadcrumbs.addBreadcrumb("Orientation changed",
                                                  attributes: attributes,
                                                  type: .system,
                                                  level: .info)
    }
#endif
    // MARK: Memory Status Listener
    
    private var source: DispatchSourceMemoryPressure?
    @objc private func observeMemoryStatusChanged() {
        if let source: DispatchSourceMemoryPressure =
            DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: DispatchQueue.main) as? DispatchSource {
            let eventHandler: DispatchSourceProtocol.DispatchSourceHandler = {
                let event: DispatchSource.MemoryPressureEvent = source.data
                if source.isCancelled == false {
                    let message = self.getMemoryWarningText(event)
                    let level = self.getMemoryWarningLevel(event)
                    _ = self.breadcrumbs.addBreadcrumb(message,
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

    // MARK: - Battery Status Listener

    @objc private func observeBatteryStatusChanged() {
#if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(notifyBatteryStatusChange),
                                               name: UIDevice.batteryLevelDidChangeNotification,
                                               object: nil)
#endif
    }
#if os(iOS)
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
        _ = breadcrumbs.addBreadcrumb(getBatteryWarningText(),
                                                      type: .system,
                                                      level: .info)
    }
#endif
}
