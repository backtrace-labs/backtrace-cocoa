// swiftlint:disable type_name
import Foundation
import CoreLocation
#if os(iOS)
import CoreTelephony
#endif

struct DefaultAttributes {
    
    static func current() -> Attributes {
        return DeviceInfo.current()
            + ScreenInfo.current()
            + LocaleInfo.current()
            + NetworkInfo.current()
            + LocationInfo.current()
            + LibInfo.current()
    }
}

protocol AttributesSourceType {
    static func current() -> Attributes
}

struct DeviceInfo: AttributesSourceType {
    
    private enum Key: String {
        // String enum values can be omitted when they are equal to the enumcase name.
        #if os(iOS)
        case deviceName = "device.name"
        case deviceModel = "device.model"
        case deviceOrientation = "device.orientation"
        case batteryState = "battery.state"
        case batteryLevel = "battery.level"
        case nfcSupported = "device.nfc.supported"
        #elseif os(tvOS)
        case deviceName = "device.name"
        case deviceModel = "device.model"
        #elseif os(macOS)
        case systemUptime = "system.uptime"
        case physicalMemory = "memory.physical"
        case processorCount = "processor.count"
        case hostname = "hostname"
        #endif
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
        #elseif os(macOS)
        let processinfo = ProcessInfo.processInfo
        deviceAttributes[Key.systemUptime.rawValue] = processinfo.systemUptime
        deviceAttributes[Key.physicalMemory.rawValue] = processinfo.physicalMemory
        deviceAttributes[Key.processorCount.rawValue] = processinfo.processorCount
        deviceAttributes[Key.hostname.rawValue] = Host.current().name
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
        #elseif os(macOS)
        case number = "screens.number"
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
        #elseif os(macOS)
        screenAttributes[Key.number.rawValue] = NSScreen.screens.count
        if let mainScreen = NSScreen.main {
            screenAttributes[Key.mainScreenWidth.rawValue] = mainScreen.frame.width
            screenAttributes[Key.mainScreenHeight.rawValue] = mainScreen.frame.height
            screenAttributes[Key.mainScreenScale.rawValue] = mainScreen.backingScaleFactor
            
        }
        #endif
        // Available onnly on iOS
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
        case locationServicesEnabled = "location.servicesEnabled"
        case locationAuthorizationStatus = "location.authorizationStatus"
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
        case .landscapeRight: return "LandsscapeRight"
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
