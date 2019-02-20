// swiftlint:disable type_name
import Foundation
#if os(iOS)
import CoreTelephony
#endif

struct DefaultAttributes {
    
    static func current() -> [String: Any] {
        var currentAttributes: [String: Any] = [:]
        currentAttributes += DeviceInfo.current()
        currentAttributes += ScreenInfo.current()
        currentAttributes += LocaleInfo.current()
        #if os(iOS)
        currentAttributes += TelephoneInfo.current()
        #endif
        currentAttributes["backtrace.version"] = BacktraceVersionNumber
        return currentAttributes
    }
}

protocol AttributesSourceType {
    static func current() -> [String: Any]
}

struct DeviceInfo: AttributesSourceType {
    
    enum Key: String {
        // String enum values can be omitted when they are equal to the enumcase name.
        #if os(iOS)
        case deviceName = "device.name"
        case deviceModel = "device.model"
        case deviceOrientation = "device.orientation"
        case batteryState = "battery.state"
        case batteryLevel = "battery.level"
        #elseif os(macOS)
        case systemUptime = "system.uptime"
        case physicalMemory = "memory.physical"
        case processorCount = "processor.count"
        #endif
    }
    
    static func current() -> [String: Any] {
        var deviceAttributes: [String: Any] = [:]
        #if os(iOS)
        let currentDevice = UIDevice.current
        deviceAttributes[Key.deviceName.rawValue] = currentDevice.name
        deviceAttributes[Key.deviceModel.rawValue] = currentDevice.model
        deviceAttributes[Key.deviceOrientation.rawValue] = currentDevice.orientation.name
        if currentDevice.isBatteryMonitoringEnabled {
            deviceAttributes[Key.batteryState.rawValue] = currentDevice.batteryState.name
            deviceAttributes[Key.batteryLevel.rawValue] = currentDevice.batteryLevel
        }
        #elseif os(macOS)
        let processinfo = ProcessInfo.processInfo
        deviceAttributes[Key.systemUptime.rawValue] = processinfo.systemUptime
        deviceAttributes[Key.physicalMemory.rawValue] = processinfo.physicalMemory
        deviceAttributes[Key.processorCount.rawValue] = processinfo.processorCount
        #endif
        return deviceAttributes
    }
}

struct ScreenInfo: AttributesSourceType {
    
    enum Key: String {
        #if os(iOS)
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
    
    static func current() -> [String: Any] {
        var screenAttributes: [String: Any] = [:]
        #if os(iOS)
        let mainScreen = UIScreen.main
        screenAttributes[Key.scale.rawValue] = mainScreen.scale
        screenAttributes[Key.width.rawValue] = mainScreen.bounds.width
        screenAttributes[Key.height.rawValue] = mainScreen.bounds.height
        screenAttributes[Key.nativeScale.rawValue] = mainScreen.nativeScale
        screenAttributes[Key.nativeWidth.rawValue] = mainScreen.nativeBounds.width
        screenAttributes[Key.nativeHeight.rawValue] = mainScreen.nativeBounds.height
        screenAttributes[Key.brightness.rawValue] = mainScreen.brightness
        #elseif os(macOS)
        screenAttributes[Key.number.rawValue] = NSScreen.screens.count
        if let mainScreen = NSScreen.main {
            screenAttributes[Key.mainScreenWidth.rawValue] = mainScreen.frame.width
            screenAttributes[Key.mainScreenHeight.rawValue] = mainScreen.frame.height
            screenAttributes[Key.mainScreenScale.rawValue] = mainScreen.backingScaleFactor
            
        }
        #endif
        return screenAttributes
    }
}

#if os(iOS)
struct TelephoneInfo: AttributesSourceType {
    
    enum Key: String {
        case carrierName = "currier.name"
        case mobileCountryCode = "currier.mobileCountryCode"
        case mobileNetworkCode = "currier.mobileNetworkCode"
        case isoCountryCode = "currier.isoCountryCode"
    }
    
    static func current() -> [String: Any] {
        let networkInfo = CTTelephonyNetworkInfo()
        var telephoneAttributes: [String: Any] = [:]
        
        var carrier: CTCarrier?
        if #available(iOS 12.0, *) {
            carrier = networkInfo.serviceSubscriberCellularProviders?.first?.value
        } else {
             carrier = networkInfo.subscriberCellularProvider
        }
        if let carrierName = carrier?.carrierName {
            telephoneAttributes[Key.carrierName.rawValue] = carrierName
        }
        if let mobileCountryCode = carrier?.mobileCountryCode {
            telephoneAttributes[Key.mobileCountryCode.rawValue] = mobileCountryCode
        }
        if let mobileNetworkCode = carrier?.mobileNetworkCode {
            telephoneAttributes[Key.mobileNetworkCode.rawValue] = mobileNetworkCode
        }
        if let isoCountryCode = carrier?.isoCountryCode {
            telephoneAttributes[Key.isoCountryCode.rawValue] = isoCountryCode
        }
        
        return telephoneAttributes
    }
}
#endif

struct LocaleInfo: AttributesSourceType {
    
    enum Key: String {
        case languageCode = "device.lang.code"
        case language = "device.lang"
        case regionCode = "device.region.code"
        case region = "device.region"
    }
    
    static func current() -> [String: Any] {
        var localeAttributes: [String: Any] = [:]
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

// swiftlint:enable type_name

private extension Dictionary {
    
    static func += (lhs: inout Dictionary, rhs: Dictionary) {
        lhs.merge(rhs) { (_, new) in new }
    }
}

#if os(iOS)
extension UIDeviceOrientation {
    
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
extension UIDevice.BatteryState {
    
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
extension UIApplication.State {
    
    var name: String {
        switch self {
        case .active: return "Active"
        case .background: return "Background"
        case .inactive: return "Inactive"
        }
    }
}
#endif
