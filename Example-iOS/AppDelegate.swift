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
        let backtraceCredentials = BacktraceCredentials(endpoint: URL(string: "https://yolo.sp.backtrace.io:6098")!,
                                                        token: "b06c6083414bf7b8e200ad994c9c8ea5d6c8fa747b6608f821278c48a4d408c3")
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
