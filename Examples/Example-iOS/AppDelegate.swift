import UIKit
import Backtrace

enum CustomError: Error {
    case runtimeError
}

func throwingFunc() throws {
    throw CustomError.runtimeError
}

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    let fileUrl = createAndWriteFile("sample.txt")

    var window: UIWindow?
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: Keys.backtraceUrl as String)!,
                                                        token: Keys.backtraceToken as String)

        let backtraceDatabaseSettings = BacktraceDatabaseSettings()
        backtraceDatabaseSettings.maxRecordCount = 10
        let backtraceConfiguration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                                  dbSettings: backtraceDatabaseSettings,
                                                                  reportsPerMin: 10,
                                                                  allowsAttachingDebugger: true,
                                                                  detectOOM: true)
        BacktraceClient.shared = try? BacktraceClient(configuration: backtraceConfiguration)
        BacktraceClient.shared?.attributes = ["foo": "bar", "testing": true]
        BacktraceClient.shared?.attachments.append(fileUrl)
        BacktraceClient.shared?.delegate = self
        
        do {
            try throwingFunc()
        } catch {
            BacktraceClient.shared?.send(attachmentPaths: []) { (result) in
                print("AppDelegate:Result:\(result)")
            }
        }

        BacktraceClient.shared?.loggingDestinations = [BacktraceBaseDestination(level: .debug)]

        // Enable error free metrics https://docs.saucelabs.com/error-reporting/web-console/overview/#stability-metrics-widgets
        BacktraceClient.shared?.metrics.enable(settings: BacktraceMetricsSettings())

        // Enable breadcrumbs https://docs.saucelabs.com/error-reporting/web-console/debug/#breadcrumbs-section
        BacktraceClient.shared?.enableBreadcrumbs()

        // Add breadcrumb
        let attributes = ["My Attribute":"My Attribute Value"]
        _ = BacktraceClient.shared?.addBreadcrumb("My Breadcrumb",
                                              attributes: attributes,
                                              type: .user,
                                              level: .error)
        return true
    }
    
    static func createAndWriteFile(_ fileName: String) -> URL {
        let dirName = "directory"
        let libraryDirectoryUrl = try! FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directoryUrl = libraryDirectoryUrl.appendingPathComponent(dirName)
        try? FileManager().createDirectory(
                    at: directoryUrl,
                    withIntermediateDirectories: false,
                    attributes: nil
                )
        let fileUrl = directoryUrl.appendingPathComponent(fileName)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let myData = formatter.string(from: Date())
        try! myData.write(to: fileUrl, atomically: true, encoding: .utf8)
        return fileUrl
    }
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
