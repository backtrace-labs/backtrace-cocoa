// swiftlint:disable type_name
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#elseif os(tvOS)
import UIKit
#endif

final class FaultInfo: AttributesSource {
    var faultMessage: String?
    
    var immutable: [String : Any?] {
        return ["error.type": "Crash"]
    }
    var mutable: [String: Any?] {
        return ["error.message": faultMessage]
    }
}

struct ProcessorInfo: AttributesSource {

    private let reportHostName: Bool

    init(reportHostName: Bool = false) {
        self.reportHostName = reportHostName
    }

    var mutable: [String: Any?] {
        let processor = try? Processor()
        let processInfo = ProcessInfo.processInfo
        let systemVmMemory = try? MemoryInfo.System()
        let systemSwapMemory = try? MemoryInfo.Swap()
        let processVmMemory = try? MemoryInfo.Process()

        return [
            // cpu
            "cpu.idle": processor?.cpuTicks.idle,
            "cpu.nice": processor?.cpuTicks.nice,
            "cpu.user": processor?.cpuTicks.user,
            "cpu.sys": processor?.cpuTicks.system,
            "cpu.process.count": processor?.processorSetLoadInfo.task_count,
            "cpu.thread.count": processor?.processorSetLoadInfo.thread_count,
            "cpu.uptime": try? System.uptime(),
            "cpu.count": processInfo.processorCount,
            "cpu.count.active": processInfo.activeProcessorCount,
            "cpu.context": processor?.taskEventsInfo.csw,
            // process
            "process.thread.count": try? ProcessInfo.numberOfThreads(),
            "process.age": try? ProcessInfo.age(),
            // system
            "system.memory.active": systemVmMemory?.active,
            "system.memory.inactive": systemVmMemory?.inactive,
            "system.memory.free": systemVmMemory?.free,
            "system.memory.used": systemVmMemory?.used,
            "system.memory.total": systemVmMemory?.total,
            "system.memory.wired": systemVmMemory?.wired,
            "system.memory.swapins": systemVmMemory?.swapins,
            "system.memory.swapouts": systemVmMemory?.swapouts,
            "system.memory.swap.total": systemSwapMemory?.total,
            "system.memory.swap.used": systemSwapMemory?.used,
            "system.memory.swap.free": systemSwapMemory?.free,
            // vm
            "vm.rss.size": processVmMemory?.resident,
            "vm.rss.peak": processVmMemory?.residentPeak,
            "vm.vma.size": processVmMemory?.virtual
        ]
    }

    var immutable: [String: Any?] {
        return [
            "cpu.boottime": try? System.boottime(),
            // hostname
            "hostname": self.reportHostName ? ProcessInfo.processInfo.hostName : "",
            // descriptor
            "descriptor.count": getdtablesize(),
            "process.starttime": try? ProcessInfo.startTime()
        ]
    }
}

struct Device: AttributesSource {

    var mutable: [String: Any?] {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let device = UIDevice.current
        var attributes: [String: Any?] = ["device.orientation": device.orientation.name]
        if device.isBatteryMonitoringEnabled {
            attributes["battery.state"] = device.batteryState.name
            attributes["battery.level"] = device.batteryLevel
        }
        if #available(iOS 11.0, *) {
            attributes["device.nfc.supported"] = true
        } else {
            attributes["device.nfc.supported"] = false
        }
        return attributes
        #else
        return [:]
        #endif
    }

    var immutable: [String: Any?] {
        return [
            "device.machine": try? System.machine(),
            "device.model": try? System.machine(),
            "uname.sysname": getSysname()
        ]
    }

    private func getSysname() -> String {
#if os(iOS) && !targetEnvironment(macCatalyst)
        return "iOS"
#elseif os(tvOS)
        return "tvOS"
#elseif os(macOS) || targetEnvironment(macCatalyst)
        return "macOS"
#else
        return "Unsupported device"
#endif
    }
}

struct ScreenInfo: AttributesSource {

    private enum Key: String {
        case count = "screens.count"
        #if (os(iOS) || os(tvOS)) && !targetEnvironment(macCatalyst)
        case scale = "screen.scale"
        case width = "screen.width"
        case height = "screen.height"
        case nativeScale = "screen.scale.native"
        case nativeWidth = "screen.width.native"
        case nativeHeight = "screen.height.native"
        case brightness = "screen.brightness"
        #elseif os(macOS) || targetEnvironment(macCatalyst)
        case mainScreenWidth = "screen.main.width"
        case mainScreenHeight = "screen.main.height"
        case mainScreenScale = "screen.main.scale"
        #endif
    }

    var immutable: [String: Any?] {
        var screenAttributes: Attributes = [:]
        #if (os(iOS) || os(tvOS)) && !targetEnvironment(macCatalyst)
        let mainScreen = UIScreen.main
        screenAttributes[Key.scale.rawValue] = mainScreen.scale
        screenAttributes[Key.width.rawValue] = mainScreen.bounds.width
        screenAttributes[Key.height.rawValue] = mainScreen.bounds.height
        screenAttributes[Key.nativeScale.rawValue] = mainScreen.nativeScale
        screenAttributes[Key.nativeWidth.rawValue] = mainScreen.nativeBounds.width
        screenAttributes[Key.nativeHeight.rawValue] = mainScreen.nativeBounds.height
        screenAttributes[Key.count.rawValue] = UIScreen.screens.count
        #elseif os(macOS) || !targetEnvironment(macCatalyst)
        screenAttributes[Key.count.rawValue] = NSScreen.screens.count
        if let mainScreen = NSScreen.main {
            screenAttributes[Key.mainScreenWidth.rawValue] = mainScreen.frame.width
            screenAttributes[Key.mainScreenHeight.rawValue] = mainScreen.frame.height
            screenAttributes[Key.mainScreenScale.rawValue] = mainScreen.backingScaleFactor
        }
        #endif

        #if os(iOS) && !targetEnvironment(macCatalyst)
        screenAttributes[Key.brightness.rawValue] = UIScreen.main.brightness
        #endif
        return screenAttributes
    }
}

struct LocaleInfo: AttributesSource {

   var immutable: [String: Any?] {
        var localeAttributes: Attributes = [:]
        if let languageCode = Locale.current.languageCode {
            localeAttributes["device.lang.code"] = languageCode
            if let language = Locale.current.localizedString(forLanguageCode: languageCode) {
                localeAttributes["device.lang"] = language
            }
        }
        if let regionCode = Locale.current.regionCode {
            localeAttributes["device.region.code"] = regionCode
            if let region = Locale.current.localizedString(forRegionCode: regionCode) {
                localeAttributes["device.region"] = region
            }
        }
        return localeAttributes
    }
}

struct NetworkInfo: AttributesSource {

     var mutable: [String: Any?] {
        return ["network.status": NetworkReachability().statusName]
    }
}

struct LibInfo: AttributesSource {

    private static let applicationGuidKey = "backtrace.unique.user.identifier"
    private static let applicationLangName = "backtrace-cocoa"

    var backtraceVersion = "2.0.6"
    
    var immutable: [String: Any?] {
        return ["guid": LibInfo.guid(store: UserDefaultsStore.self).uuidString,
                "lang.name": LibInfo.applicationLangName,
                "lang.version": backtraceVersion,
                "backtrace.version": backtraceVersion,
                "backtrace.agent": "backtrace-cocoa"]
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

struct ApplicationInfo: AttributesSource {
    private static let session = UUID().uuidString

    var immutable: [String: Any?] {
        return ["application.version": Backtrace.applicationVersion,
             "application.build": Backtrace.buildVersion,
             "application.session": ApplicationInfo.session];
    }
}

struct BreadcrumbsInfo: AttributesSource {
    internal static var currentBreadcrumbsId: Int?
    internal static var breadcrumbFile: URL?

    var mutable: [String: Any?] {
        if let currentBreadcrumbsId = BreadcrumbsInfo.currentBreadcrumbsId {
            return ["breadcrumbs.lastId": currentBreadcrumbsId]
        }
        return [:]
    }

    var attachments: Attachments {
        if let breadcrumbFile = BreadcrumbsInfo.breadcrumbFile {
            return [breadcrumbFile]
        }
        return []
    }
}

// swiftlint:enable type_name

#if os(iOS) && !targetEnvironment(macCatalyst)
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
        @unknown default:
            return "Unknown"
        }
    }
}
#endif

#if os(iOS) && !targetEnvironment(macCatalyst)
private extension UIDevice.BatteryState {

    var name: String {
        switch self {
        case .charging: return "Charging"
        case .full: return "Full"
        case .unknown: return "Unknown"
        case .unplugged: return "Unplugged"
        @unknown default:
            return "Unknown"
        }
    }
}
#endif

#if os(iOS) && !targetEnvironment(macCatalyst)
private extension UIApplication.State {

    var name: String {
        switch self {
        case .active: return "Active"
        case .background: return "Background"
        case .inactive: return "Inactive"
        @unknown default:
            return "Unknown"
        }
    }
}
#endif
