import Foundation

@objc public enum BacktraceBreadcrumbType: Int {

    case manual = 1
    case log = 2
    case navigation = 3
    case http = 4
    case system = 5
    case user = 6
    case configuration = 7

    var description: String {
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

    var description: String {
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

    private let breadcrumbSettings: BacktraceBreadcrumbSettings = BacktraceBreadcrumbSettings()
    private var breadcrumbsLogManager: BacktraceBreadcrumbsLogManager?
    private var backtraceComponentListener: BacktraceComponentListener?

    public func enableBreadcrumbs(_ breadcrumbSettings: BacktraceBreadcrumbSettings = BacktraceBreadcrumbSettings()) {
        do {
            breadcrumbsLogManager = try BacktraceBreadcrumbsLogManager(breadcrumbSettings: breadcrumbSettings)
            if breadcrumbSettings.breadcrumbTypes.contains(where: { $0.rawValue == BacktraceBreadcrumbType.system.rawValue }) {
                backtraceComponentListener = BacktraceComponentListener()
            }
            try BreadcrumbsInfo.breadcrumbFile = breadcrumbSettings.getBreadcrumbLogPath()
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen enabling breadcrumbs, breadcrumbs is disabled")
            disableBreadcrumbs()
        }

        _ = addBreadcrumb("Breadcrumbs enabled.")
    }

    public func disableBreadcrumbs() {
        breadcrumbSettings.breadcrumbTypes.removeAll()
        self.backtraceComponentListener = nil
        self.breadcrumbsLogManager = nil

        // Remove breadcrumbs attachment
        BreadcrumbsInfo.breadcrumbFile = nil

        // Remove currentBreadcrumbsId, which prevents it from being added
        BreadcrumbsInfo.currentBreadcrumbsId = nil

    }

    func addBreadcrumb(_ message: String,
                       attributes: [String: String]? = nil,
                       type: BacktraceBreadcrumbType = BacktraceBreadcrumbType.manual,
                       level: BacktraceBreadcrumbLevel = BacktraceBreadcrumbLevel.info) -> Bool {
        if let breadcrumbsLogManager = breadcrumbsLogManager, allowBreadcrumbsToAdd(level) {
            return breadcrumbsLogManager.addBreadcrumb(message, attributes: attributes, type: type, level: level)
        }
        return false
    }

    func allowBreadcrumbsToAdd(_ level: BacktraceBreadcrumbLevel) -> Bool {
        return isBreadcrumbsEnabled && breadcrumbSettings.breadcrumbLevel.rawValue >= level.rawValue
    }
    
    var isBreadcrumbsEnabled: Bool {
        return !breadcrumbSettings.breadcrumbTypes.isEmpty
    }

    var getCurrentBreadcrumbId: Int? {
        return breadcrumbsLogManager?.getCurrentBreadcrumbId
    }
}
