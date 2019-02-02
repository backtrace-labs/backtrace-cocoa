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
                                                        token: "")
        BacktraceClient.shared.register(credentials: backtraceCredentials)
        BacktraceClient.shared.delegate = self

        do {
            try throwingFunc()
        } catch {
            BacktraceClient.shared.send { (result) in
                print(result)
            }
        }

        return true
    }
}

extension AppDelegate: BacktraceClientDelegate {
    func willSend(_ report: BacktraceCrashReport) -> (BacktraceCrashReport) {
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
