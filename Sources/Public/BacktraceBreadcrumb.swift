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
    
    var info : String {
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
    
    var info : String {
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

@objc public protocol BacktraceBreadcrumbProtocol {
    @objc func addBreadcrumb(_ message: String,
                        attributes: [String:Any],
                        type: BacktraceBreadcrumbType,
                        level: BacktraceBreadcrumbLevel) -> Bool
    @objc func addBreadcrumb(_ message: String) -> Bool
    @objc func addBreadcrumb(_ message: String,
                        attributes: [String:Any]) -> Bool
    @objc func addBreadcrumb(_ message: String,
                        type: BacktraceBreadcrumbType,
                        level: BacktraceBreadcrumbLevel) -> Bool
    @objc func addBreadcrumb(_ message: String,
                        level: BacktraceBreadcrumbLevel) -> Bool
    @objc func addBreadcrumb(_ message: String,
                        type: BacktraceBreadcrumbType) -> Bool
}

@objc public class BacktraceBreadcrumb: NSObject {
    
    private var enabledBreadcrumbTypes = [BacktraceBreadcrumbType]()
        
    private static let breadcrumbLogFileName = "bt-breadcrumbs-0"

    public static var defaultMaxLogSize = 64000;
#if os(iOS)
    private var breadcrumbsLogManager: BacktraceBreadcrumbsLogManager?
    private var backtraceComponentListener: BacktraceComponentListener?
#endif
    private func breadcrumbLogPath() throws -> String {
        var fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        fileURL.appendPathComponent(BacktraceBreadcrumb.breadcrumbLogFileName)
        return fileURL.path
    }
    
    public func enableBreadCrumbs(_ breadCrumbTypes: [BacktraceBreadcrumbType] = BacktraceBreadcrumbType.all , maxLogSize: Int = defaultMaxLogSize) {
        do {
#if os(iOS)
            let fileURLPath = try breadcrumbLogPath()
            breadcrumbsLogManager = BacktraceBreadcrumbsLogManager(fileURLPath, maxQueueFileSizeBytes: BacktraceBreadcrumb.defaultMaxLogSize)
            enabledBreadcrumbTypes = breadCrumbTypes
            if let _ = breadCrumbTypes.first(where: { $0.rawValue == BacktraceBreadcrumbType.system.rawValue }) {
                backtraceComponentListener = BacktraceComponentListener()
            }
#endif
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen enable breadcrumbs")
        }
    }
    
    public func disableBreadCrumbs() {
        enabledBreadcrumbTypes.removeAll()
#if os(iOS)
        self.backtraceComponentListener = nil
#endif
    }
    
    public func addBreadcrumb(_ message: String,
                              attributes:[String:Any]? = nil,
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
        return !enabledBreadcrumbTypes.isEmpty
    }
    
#if os(iOS)
    var getCurrentBreadcrumbId : Int? {
        return breadcrumbsLogManager?.getCurrentBreadcrumbId
    }
#endif
    public func processReportBreadcrumbs(_ report: inout BacktraceReport) {
#if os(iOS)
        if !isBreadcrumbsEnabled {
            return
        }
        guard let lastBreadcrumbId = getCurrentBreadcrumbId else {
            return
        }
        do {
            let fileURLPath = try breadcrumbLogPath()
            report.attachmentPaths.append(fileURLPath)
            report.attributes["breadcrumbs.lastId"] = lastBreadcrumbId
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen processing breadcrumbs report")
        }
#endif
    }
}
