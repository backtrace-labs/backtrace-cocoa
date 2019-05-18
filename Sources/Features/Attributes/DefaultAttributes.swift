// swiftlint:disable type_name
import Foundation
import CoreLocation

struct DefaultAttributes {
    
    static func current() -> Attributes {
        return [DeviceInfo.current(),
                ScreenInfo.current(),
                LocaleInfo.current(),
                NetworkInfo.current(),
                LocationInfo.current(),
                LibInfo.current(),
                ProcessorInfo.current()]
            .reduce([:], +)
    }
}

protocol AttributesSourceType {
    static func current() -> Attributes
}

struct ProcessorInfo: AttributesSourceType {
    
    private enum Key: String {
        case cpuContext = "cpu.context"
        case cpuIdle = "cpu.idle"
        case cpuIowait = "cpu.iowait"
        case cpuIrq = "cpu.irq"
        case cpuKernel = "cpu.kernel"
        case cpuNice = "cpu.nice"
        case cpuProcessBlocked = "cpu.process.blocked"
        case cpuProcessCount = "cpu.process.count"
        case cpuProcessRunning = "cpu.process.running"
        case cpuSoftirq = "cpu.softirq"
        case cpuUser = "cpu.user"
        case cpuSystem = "cpu.system"
        case descriptorCount = "descriptor.count"
        case processThreadCount = "process.thread.count"
        case systemBoottime = "cpu.boottime"
        case processorCount = "cpu.count"
        case processorActive = "cpu.active"
        case hostname = "hostname"
    }
    
    static func current() -> Attributes {
        let processor = try? Processor()
        let processinfo = ProcessInfo.processInfo
        
        let keyValuePairs: [String: Any?] = [
            Key.cpuIdle.rawValue: processor?.cpuTicks.idle,
            Key.cpuNice.rawValue: processor?.cpuTicks.nice,
            Key.cpuUser.rawValue: processor?.cpuTicks.user,
            Key.cpuSystem.rawValue: processor?.cpuTicks.system,
            Key.descriptorCount.rawValue: getdtablesize(),
            Key.cpuProcessCount.rawValue: processor?.processorSetLoadInfo.task_count,
            Key.processThreadCount.rawValue: processor?.processorSetLoadInfo.thread_count,
            Key.hostname.rawValue: processinfo.hostName,
            Key.systemBoottime.rawValue: try? System.boottime(),
            Key.processorCount.rawValue: processinfo.processorCount,
            Key.processorActive.rawValue: processinfo.activeProcessorCount,
            Key.cpuContext.rawValue: processor?.taskEventsInfo.csw]
        
        return keyValuePairs.compactMapValues { $0 }
    }
}

struct DeviceInfo: AttributesSourceType {
    
    private enum Key: String {
        #if os(iOS)
        case deviceOrientation = "device.orientation"
        case batteryState = "battery.state"
        case batteryLevel = "battery.level"
        case nfcSupported = "device.nfc.supported"
        #endif
        case deviceName = "device.name"
        case deviceModel = "device.model"
    }
    
    static func current() -> Attributes {
        var deviceAttributes: Attributes = [:]
        #if os(iOS)
        let currentDevice = UIDevice.current
        deviceAttributes[Key.deviceName.rawValue] = currentDevice.name
        deviceAttributes[Key.deviceModel.rawValue] = currentDevice.model
        deviceAttributes[Key.deviceOrientation.rawValue] = currentDevice.orientation.name
        if currentDevice.isBatteryMonitoringEnabled {
            deviceAttributes[Key.batteryState.rawValue] = currentDevice.batteryState.name
            deviceAttributes[Key.batteryLevel.rawValue] = currentDevice.batteryLevel
        }
        if #available(iOS 11.0, *) {
            deviceAttributes[Key.nfcSupported.rawValue] = true
        } else {
            deviceAttributes[Key.nfcSupported.rawValue] = false
        }
        #elseif os(tvOS)
        let currentDevice = UIDevice.current
        deviceAttributes[Key.deviceName.rawValue] = currentDevice.name
        deviceAttributes[Key.deviceModel.rawValue] = currentDevice.model
        #endif
        return deviceAttributes
    }
}

struct ScreenInfo: AttributesSourceType {
    
    private enum Key: String {
        #if os(iOS) || os(tvOS)
        case scale = "screen.scale"
        case width = "screen.width"
        case height = "screen.height"
        case nativeScale = "screen.scale.native"
        case nativeWidth = "screen.width.native"
        case nativeHeight = "screen.height.native"
        case brightness = "screen.brightness"
        case count = "screens.count"
        #elseif os(macOS)
        case count = "screens.count"
        case mainScreenWidth = "screen.main.width"
        case mainScreenHeight = "screen.main.height"
        case mainScreenScale = "screen.main.scale"
        #endif
    }
    
    static func current() -> Attributes {
        var screenAttributes: Attributes = [:]
        #if os(iOS) || os(tvOS)
        let mainScreen = UIScreen.main
        screenAttributes[Key.scale.rawValue] = mainScreen.scale
        screenAttributes[Key.width.rawValue] = mainScreen.bounds.width
        screenAttributes[Key.height.rawValue] = mainScreen.bounds.height
        screenAttributes[Key.nativeScale.rawValue] = mainScreen.nativeScale
        screenAttributes[Key.nativeWidth.rawValue] = mainScreen.nativeBounds.width
        screenAttributes[Key.nativeHeight.rawValue] = mainScreen.nativeBounds.height
        screenAttributes[Key.count.rawValue] = UIScreen.screens.count
        #elseif os(macOS)
        screenAttributes[Key.count.rawValue] = NSScreen.screens.count
        if let mainScreen = NSScreen.main {
            screenAttributes[Key.mainScreenWidth.rawValue] = mainScreen.frame.width
            screenAttributes[Key.mainScreenHeight.rawValue] = mainScreen.frame.height
            screenAttributes[Key.mainScreenScale.rawValue] = mainScreen.backingScaleFactor
        }
        #endif
        
        #if os(iOS)
        screenAttributes[Key.brightness.rawValue] = UIScreen.main.brightness
        #endif
        return screenAttributes
    }
}

struct LocaleInfo: AttributesSourceType {
    
    private enum Key: String {
        case languageCode = "device.lang.code"
        case language = "device.lang"
        case regionCode = "device.region.code"
        case region = "device.region"
    }
    
    static func current() -> Attributes {
        var localeAttributes: Attributes = [:]
        if let languageCode = Locale.current.languageCode {
            localeAttributes[Key.languageCode.rawValue] = languageCode
            if let language = Locale.current.localizedString(forLanguageCode: languageCode) {
                localeAttributes[Key.language.rawValue] = language
            }
        }
        if let regionCode = Locale.current.regionCode {
            localeAttributes[Key.regionCode.rawValue] = regionCode
            if let region = Locale.current.localizedString(forRegionCode: regionCode) {
                localeAttributes[Key.region.rawValue] = region
            }
        }
        return localeAttributes
    }
}

struct NetworkInfo: AttributesSourceType {
    
    private enum Key: String {
        case status = "network.status"
    }
    
    static func current() -> Attributes {
        var networkAttributes: Attributes = [:]
        networkAttributes[Key.status.rawValue] = NetworkReachability().statusName
        return networkAttributes
    }
}

struct LocationInfo: AttributesSourceType {
    
    private enum Key: String {
        case locationServicesEnabled = "location.enabled"
        case locationAuthorizationStatus = "location.authorization.status"
    }
    static func current() -> [String: Any] {
        var locationAttributes: [String: Any] = [:]
        locationAttributes[Key.locationServicesEnabled.rawValue] = CLLocationManager.locationServicesEnabled()
        locationAttributes[Key.locationAuthorizationStatus.rawValue] = CLLocationManager.authorizationStatus().name
        return locationAttributes
    }
}

struct LibInfo: AttributesSourceType {
    
    private static let applicationGuidKey = "backtrace.unique.user.identifier"
    private static let applicationLangName = "backtrace-cocoa"
    
    private enum Key: String {
        case guid = "guid"
        case langName = "lang.name"
        case langVersion = "lang.version"
    }
    
    static func current() -> Attributes {
        return [Key.guid.rawValue: guid(store: UserDefaultsStore.self).uuidString,
                Key.langName.rawValue: applicationLangName,
                Key.langVersion.rawValue: BacktraceVersionNumber]
    }
    
    static private func guid(store: UserDefaultsStore.Type) -> UUID {
        if let uuidString: String = store.value(forKey: applicationGuidKey), let uuid = UUID(uuidString: uuidString) {
            return uuid
        } else {
            let uuid = UUID()
            store.store(uuid.uuidString, forKey: applicationGuidKey)
            return uuid
        }
    }
}
// swiftlint:enable type_name

private extension CLAuthorizationStatus {
    
    var name: String {
        switch self {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "WhenInUse"
        case .denied: return "Denied"
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        }
    }
}

#if os(iOS)
private extension UIDeviceOrientation {
    
    var name: String {
        switch self {
        case .faceDown: return "FaceDown"
        case .faceUp: return "FaceUp"
        case .landscapeLeft: return "LandscapeLeft"
        case .landscapeRight: return "LandscapeRight"
        case .portrait: return "Portrait"
        case .portraitUpsideDown: return "PortraitUpsideDown"
        case .unknown: return "Unknown"
        }
    }
}
#endif

#if os(iOS)
private extension UIDevice.BatteryState {
    
    var name: String {
        switch self {
        case .charging: return "Charging"
        case .full: return "Full"
        case .unknown: return "Unknown"
        case .unplugged: return "Unplagged"
        }
    }
}
#endif

#if os(iOS)
private extension UIApplication.State {
    
    var name: String {
        switch self {
        case .active: return "Active"
        case .background: return "Background"
        case .inactive: return "Inactive"
        }
    }
}
#endif
