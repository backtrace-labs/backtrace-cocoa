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
        backtraceDatabaseSettings.maxRecordCount = 1000
        backtraceDatabaseSettings.maxDatabaseSize = 10
        backtraceDatabaseSettings.retryInterval = 5
        backtraceDatabaseSettings.retryLimit = 3
        backtraceDatabaseSettings.retryBehaviour = RetryBehaviour.interval
        backtraceDatabaseSettings.retryOrder = RetryOrder.queue
        let backtraceConfiguration = BacktraceClientConfiguration(credentials: backtraceCredentials,
                                                                  dbSettings: backtraceDatabaseSettings,
                                                                  reportsPerMin: 10,
                                                                  allowsAttachingDebugger: true)

        BacktraceClient.shared = try? BacktraceClient(configuration: backtraceConfiguration)
        BacktraceClient.shared?.delegate = self
        BacktraceClient.shared?.attributes = ["foo": "bar", "testing": true]

        do {
            try throwingFunc()
        } catch {
            let filePath = Bundle.main.path(forResource: "test", ofType: "txt")!
            BacktraceClient.shared?.send(attachmentPaths: [filePath]) { (result) in
                print("AppDelegate:Result:\(result)")
            }
        }

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
