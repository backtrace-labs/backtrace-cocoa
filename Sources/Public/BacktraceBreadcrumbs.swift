import Foundation
// swiftlint:disable trailing_whitespace

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
    case http = 4
    case error = 5
    case fatal = 6
    
    var description: String {
        switch self {
        case .debug:
            return "debug"
        case .info:
            return "info"
        case .warning:
            return "warning"
        case .http:
            return "http"
        case .error:
            return "error"
        case .fatal:
            return "fatal"
        }
    }
    
    public static let all: [BacktraceBreadcrumbLevel] = [.debug, .info, .warning, .http, .error, .fatal]
    
    public static let none: [BacktraceBreadcrumbLevel] = []
}

@objc public class BacktraceBreadcrumbs: NSObject {
    
    private var breadcrumbSettings = BacktraceBreadcrumbSettings()

#if os(iOS)
    private var breadcrumbsLogManager: BacktraceBreadcrumbsLogManager?
    private var backtraceComponentListener: BacktraceComponentListener?
#endif

    @objc public override init() {
        super.init()
        enableBreadcrumbs()
    }
    
    @objc public init(_ breadcrumbSettings: BacktraceBreadcrumbSettings) {
        super.init()
        enableBreadcrumbs(breadcrumbSettings)
    }
    
    public func enableBreadcrumbs(_ breadcrumbSettings: BacktraceBreadcrumbSettings = BacktraceBreadcrumbSettings()) {
        do {
#if os(iOS)
            breadcrumbsLogManager = try BacktraceBreadcrumbsLogManager(breadcrumbSettings: breadcrumbSettings)
            self.breadcrumbSettings = breadcrumbSettings
            if breadcrumbSettings.breadcrumbTypes.first(where: { $0.rawValue == BacktraceBreadcrumbType.system.rawValue }) != nil {
                backtraceComponentListener = BacktraceComponentListener()
            }
#endif
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen enable breadcrumbs")
        }
    }
    
    public func disableBreadcrumbs() {
        breadcrumbSettings.breadcrumbTypes.removeAll()
#if os(iOS)
        self.backtraceComponentListener = nil
#endif
    }
    
    func addBreadcrumb(_ message: String,
                              attributes: [String: String]? = nil,
                              type: BacktraceBreadcrumbType = BacktraceBreadcrumbType.manual,
                              level: BacktraceBreadcrumbLevel = BacktraceBreadcrumbLevel.info) -> Bool {
#if os(iOS)
        if let breadcrumbsLogManager = breadcrumbsLogManager, isBreadcrumbsEnabled {
            return breadcrumbsLogManager.addBreadcrumb(message, attributes: attributes, type: type, level: level)
        }
#endif
        return false
    }
    
    var isBreadcrumbsEnabled: Bool {
        return !breadcrumbSettings.breadcrumbTypes.isEmpty
    }
    
#if os(iOS)
    var getCurrentBreadcrumbId: Int? {
        return breadcrumbsLogManager?.getCurrentBreadcrumbId
    }
#endif
    public func processReportBreadcrumbs(_ report: inout BacktraceReport) {
#if os(iOS)
        guard let lastBreadcrumbId = getCurrentBreadcrumbId else {
            return
        }
        do {
            let breadcrumbLogPath = try breadcrumbSettings.getBreadcrumbLogPath()
            report.attachmentPaths.append(breadcrumbLogPath)
            report.attributes["breadcrumbs.lastId"] = lastBreadcrumbId
        } catch {
            BacktraceLogger.warning("When attaching breadcremb file with crash report.")
        }
#endif
    }
}
