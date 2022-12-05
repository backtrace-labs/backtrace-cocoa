import UIKit
import Backtrace

enum CustomError: Error {
    case runtimeError
}

func throwingFunc() throws {
    throw CustomError.runtimeError
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

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
                                                                  allowsAttachingDebugger: true)

        BacktraceClient.shared = try? BacktraceClient(configuration: backtraceConfiguration)
        BacktraceClient.shared?.delegate = self
        BacktraceClient.shared?.enableBreadcrumbs()

        BacktraceClient.shared?.attributes = ["foo": "bar", "testing": true]

        do {
            try throwingFunc()
        } catch {
            let filePath = Bundle.main.path(forResource: "test", ofType: "txt")!
            BacktraceClient.shared?.send(attachmentPaths: [filePath]) { (result) in
                print("AppDelegate:Result:\(result)")
            }
        }

        let attributes = ["My Attribute":"My Attribute Value"]
        _ = BacktraceClient.shared?.addBreadcrumb("My Breadcrumb",
                                              attributes: attributes,
                                              type: .user,
                                              level: .error)

        // Enable error free metrics https://docs.saucelabs.com/error-reporting/web-console/overview/#stability-metrics-widgets
        BacktraceClient.shared?.metrics.enable(settings: BacktraceMetricsSettings())

        return true
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
