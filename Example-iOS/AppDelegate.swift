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
        let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://backtrace.io")!,
                                                        token: "token")
        let configuration = BacktraceClientConfiguration(credentials: backtraceCredentials)
        
        BacktraceClient.shared = try? BacktraceClient(configuration: configuration)
        BacktraceClient.shared?.delegate = self
        BacktraceClient.shared?.userAttributes = ["foo": "bar", "testing": true]

        do {
            try throwingFunc()
        } catch {
            BacktraceClient.shared?.send { (result) in
                print(result)
            }
        }

        return true
    }
}

extension AppDelegate: BacktraceClientDelegate {
    func willSend(_ report: BacktraceReport) -> (BacktraceReport) {
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
