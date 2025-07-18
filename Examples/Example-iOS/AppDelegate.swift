import UIKit
import Backtrace
import CrashReporter

enum CustomError: Error {
    case runtimeError
}

func throwingFunc() throws {
    throw CustomError.runtimeError
}

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Usage https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#usage
        let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: Keys.backtraceUrl as String)!, token: Keys.backtraceToken as String)

        // Customize Database Settings https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#database-settings
        let backtraceDatabaseSettings = BacktraceDatabaseSettings()
        backtraceDatabaseSettings.maxRecordCount = 10
        
        // BacktraceClientConfiguration https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#advanced-usage
        let backtraceConfiguration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                                  dbSettings: backtraceDatabaseSettings,
                                                                  reportsPerMin: 10,
                                                                  allowsAttachingDebugger: true,
                                                                  detectOOM: true)
        
        // Customize PLCrashReporterConfig with custom basePath https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#plcrashreporter
        guard let plcrashReporterConfig = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all) else {
            fatalError("Could not create PLCrashReporterConfig")
        }
        
        let reporter = BacktraceCrashReporter(config: plcrashReporterConfig)
        
        // BacktraceClient
        BacktraceClient.shared = try? BacktraceClient(configuration: backtraceConfiguration, crashReporter: reporter)
        
        // Attributes https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#attributes
        BacktraceClient.shared?.attributes = ["foo": "bar", "testing": true]
        
        // File Attachments https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#file-attachments
        BacktraceClient.shared?.attachments.append(sampleAttachmentURL)
        
        // Handling Delegate events https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#handling-events
        BacktraceClient.shared?.delegate = self

        BacktraceClient.shared?.loggingDestinations = [BacktraceBaseDestination(level: .debug)]

        // Enable error free metrics https://docs.saucelabs.com/error-reporting/web-console/overview/#stability-metrics-widgets
        BacktraceClient.shared?.metrics.enable(settings: BacktraceMetricsSettings())

        // Enable breadcrumbs https://docs.saucelabs.com/error-reporting/web-console/debug/#breadcrumbs-section
        BacktraceClient.shared?.enableBreadcrumbs()

        // Add breadcrumbs https://docs.saucelabs.com/error-reporting/platform-integrations/ios/configuration/#breadcrumbs
        let attributes = ["My Attribute":"My Attribute Value"]
        _ = BacktraceClient.shared?.addBreadcrumb("My Breadcrumb",
                                                  attributes: attributes,
                                                  type: .user,
                                                  level: .error)
        // Sample throwing method
        do {
            try throwingFunc()
        } catch {
            BacktraceClient.shared?.send(attachmentPaths: []) { (result) in
                print("AppDelegate:Result:\(result)")
            }
        }
        return true
    }
    
    /// Custom directory with FileProtectionType.none
    private lazy var crashDirectory: URL = {
        do {
            return try FileManager.default.createCustomDirectory(
                name: "btcrash",
                protection: .none
            )
        } catch {
            fatalError("Failed to create crash directory: \(error)")
        }
    }()
    
    /// Sample attachment
    private lazy var sampleAttachmentURL: URL = {
        do {
            let attachmentsDir = try FileManager.default.createCustomDirectory(
                name: "attachment",
                protection: .none
            )
            let fileURL = attachmentsDir.appendingPathComponent("sample.txt")
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            let content = formatter.string(from: Date())
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            fatalError("Failed to write sample attachment: \(error)")
        }
    }()
}

extension AppDelegate: BacktraceClientDelegate {
    func willSend(_ report: BacktraceReport) -> BacktraceReport {
        print("AppDelegate: willSend")
        return report
    }
    
    func willSendRequest(_ request: URLRequest) -> URLRequest {
        print("AppDelegate: willSendRequest")
        return request
    }
    
    func serverDidRespond(_ result: BacktraceResult) {
        print("AppDelegate:serverDidRespond: \(result)")
    }
    
    func connectionDidFail(_ error: Error) {
        print("AppDelegate: connectionDidFail: \(error)")
    }
    
    func didReachLimit(_ result: BacktraceResult) {
        print("AppDelegate: didReachLimit: \(result)")
    }
}

extension FileManager {
    func createCustomDirectory(name: String, protection: FileProtectionType) throws -> URL {
        let base = try url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
        
        print("Crash directory path: \(dir.path)")

        return dir
    }
}
