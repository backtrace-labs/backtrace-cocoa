import Foundation

@objc public enum BacktraceBreadcrumbType: Int, Sendable {

    case manual = 1
    case log = 2
    case navigation = 3
    case http = 4
    case system = 5
    case user = 6
    case configuration = 7

    public var description: String {
        switch self {
        case .manual:
            return "manual"
        case .log:
            return "log"
        case .navigation:
            return "navigation"
        case .http:
            return "http"
        case .system:
            return "system"
        case .user:
            return "user"
        case .configuration:
            return "configuration"
        }
    }

    public static let all: [BacktraceBreadcrumbType] = [.manual, .log, .navigation, .http, .system, .user, .configuration]

    public static let none: [BacktraceBreadcrumbType] = []
}

@objc public enum BacktraceBreadcrumbLevel: Int {

    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case fatal = 5

    public var description: String {
        switch self {
        case .debug:
            return "debug"
        case .info:
            return "info"
        case .warning:
            return "warning"
        case .error:
            return "error"
        case .fatal:
            return "fatal"
        }
    }
}

@objc public class BacktraceBreadcrumbs: NSObject {

    private var breadcrumbsLogManager: BacktraceBreadcrumbsLogManager?
    private var backtraceNotificationObserver: BacktraceNotificationObserver?
    private var breadcrumbLevel: BacktraceBreadcrumbLevel?
    private var breadcrumbTypes: [BacktraceBreadcrumbType]?
    private(set) var isBreadcrumbsEnabled: Bool = false

    public func enableBreadcrumbs(_ breadcrumbSettings: BacktraceBreadcrumbSettings = BacktraceBreadcrumbSettings()) async {
        do {
            self.breadcrumbLevel = breadcrumbSettings.breadcrumbLevel
            self.breadcrumbTypes = breadcrumbSettings.breadcrumbTypes
            self.breadcrumbsLogManager = try BacktraceBreadcrumbsLogManager(breadcrumbSettings: breadcrumbSettings)
            if breadcrumbSettings.breadcrumbTypes.contains(where: { $0.rawValue == BacktraceBreadcrumbType.system.rawValue }) {
                backtraceNotificationObserver = BacktraceNotificationObserver(breadcrumbs: self)
                backtraceNotificationObserver?.enableNotificationObserver()
            }

            try BreadcrumbsInfo.breadcrumbFile = breadcrumbSettings.getBreadcrumbLogPath()

            isBreadcrumbsEnabled = true
            _ = await addBreadcrumb("Breadcrumbs enabled.", type: .system)
        } catch {
            await BacktraceLogger.warning("\(error.localizedDescription) \nWhen enabling breadcrumbs, breadcrumbs is disabled")
            // disable breadcrumbs, to not leave the class half initialized (errors can be thrown from various dependencies)
            disableBreadcrumbs()
        }
    }

    public func disableBreadcrumbs() {
        self.isBreadcrumbsEnabled = false
        self.backtraceNotificationObserver = nil
        self.breadcrumbsLogManager = nil
        self.breadcrumbTypes = nil
        self.breadcrumbLevel = nil

        // Remove breadcrumbs attachment
        BreadcrumbsInfo.breadcrumbFile = nil

        // Remove currentBreadcrumbsId, which prevents it from being added to reports
        BreadcrumbsInfo.currentBreadcrumbsId = nil
    }

    public func addBreadcrumb(_ message: String,
                       attributes: [String: String]? = nil,
                       type: BacktraceBreadcrumbType = BacktraceBreadcrumbType.manual,
                              level: BacktraceBreadcrumbLevel = BacktraceBreadcrumbLevel.info) async -> Bool {
        if let breadcrumbsLogManager = breadcrumbsLogManager, allowBreadcrumbsToAdd(level) {
            return await breadcrumbsLogManager.addBreadcrumb(message, attributes: attributes, type: type, level: level)
        }
        return false
    }

    func allowBreadcrumbsToAdd(_ level: BacktraceBreadcrumbLevel) -> Bool {
        guard let breadcrumbLevel = self.breadcrumbLevel else {
            return false
        }

        return isBreadcrumbsEnabled && breadcrumbLevel.rawValue <= level.rawValue
    }

    public func clear() async -> Bool {
        return await breadcrumbsLogManager?.clear() ?? false
    }

    public var getCurrentBreadcrumbId: Int? {
        return breadcrumbsLogManager?.getCurrentBreadcrumbId
    }
}
