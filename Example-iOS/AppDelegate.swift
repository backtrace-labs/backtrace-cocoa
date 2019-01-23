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
        let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "")!,
                                                        token: "")
        BacktraceClient.shared.register(credentials: backtraceCredentials)
        
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
