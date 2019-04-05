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
        let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://sp.backtrace.io")!,
                                                        token: "token")
        let backtraceDatabaseSettings = BacktraceDatabaseSettings()
        backtraceDatabaseSettings.maxRecordCount = 1000
        backtraceDatabaseSettings.maxDatabaseSize = 10
        backtraceDatabaseSettings.retryInterval = 5
        backtraceDatabaseSettings.retryLimit = 3
        backtraceDatabaseSettings.retryBehaviour = RetryBehaviour.interval
        backtraceDatabaseSettings.retryOrder = RetryOder.queue
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
                print(result)
            }
        }

        return true
    }
}

extension AppDelegate: BacktraceClientDelegate {
    func willSend(_ report: BacktraceReport) -> (BacktraceReport) {
        report.attributes["added"] = "just before send"
        return report
    }

    func willSendRequest(_ request: URLRequest) -> URLRequest {
        return request
    }

    func serverDidFail(_ error: Error) {

    }

    func serverDidResponse(_ result: BacktraceResult) {

    }

    func didReachLimit(_ result: BacktraceResult) {

    }
}
