import Foundation

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
            return "MANUAL"
        case .log:
            return "LOG"
        case .navigation:
            return "NAVIGATION"
        case .http:
            return "HTTP"
        case .system:
            return "SYSTEM"
        case .user:
            return "USER"
        case .configuration:
            return "CONFIGURATION"
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
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .http:
            return "HTTP"
        case .error:
            return "ERROR"
        case .fatal:
            return "FATAL"
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
        
    private static let breadcrumbLogFileName = "bt-breadcrumbs-0.json";

    public static var DEFAULT_MAX_LOG_SIZE_BYTES = 64000;
        
    private var breadcrumbsLogManager: BacktraceBreadcrumbsLogManager?
    
    public func enableBreadCrumbs(_ breadCrumbTypes: [BacktraceBreadcrumbType] = BacktraceBreadcrumbType.all , maxLogSize: Int = DEFAULT_MAX_LOG_SIZE_BYTES) {
        self.enabledBreadcrumbTypes = breadCrumbTypes
        
        do {
             var fileURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            fileURL.appendPathComponent(BacktraceBreadcrumb.breadcrumbLogFileName)
                print(fileURL.path)
            breadcrumbsLogManager = BacktraceBreadcrumbsLogManager(fileURL.path, maxQueueFileSizeBytes: BacktraceBreadcrumb.DEFAULT_MAX_LOG_SIZE_BYTES)
            
        } catch {
            BacktraceLogger.warning("\(error.localizedDescription) \nWhen enable breadcrumbs")
        }
    }
    
    public func disableBreadCrumbs() {
        enabledBreadcrumbTypes.removeAll()
    }
    
    public func addBreadcrumb(_ message: String,
                              attributes:[String:Any]? = nil,
                              type: BacktraceBreadcrumbType = BacktraceBreadcrumbType.manual,
                              level: BacktraceBreadcrumbLevel = BacktraceBreadcrumbLevel.info) -> Bool {
        if  let breadcrumbsLogManager = breadcrumbsLogManager, isBreadcrumbsEnabled {
            return breadcrumbsLogManager.addBreadcrumb(message, attributes: attributes, type: type, level: level)
        }
        return false
    }
    
    private var isBreadcrumbsEnabled: Bool {
        return enabledBreadcrumbTypes.count > 0
    }
}
