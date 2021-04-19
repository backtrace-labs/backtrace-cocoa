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
        
        let fileName = "sample.txt"
        guard let fileUrl = try? createAndWriteFile(fileName) else {
            print("Could not create the file attachment")
            return false
        }
        var crashAttachments = Attachments()
        crashAttachments.append(fileUrl)
        BacktraceClient.shared?.attachments = crashAttachments

        BacktraceClient.shared?.loggingDestinations = [BacktraceBaseDestination(level: .debug)]
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
    
    func createAndWriteFile(_ fileName: String) throws -> URL {
        let dirName = "directory"
        guard let libraryDirectoryUrl = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            throw CustomError.runtimeError
        }
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
        try myData.write(to: fileUrl, atomically: true, encoding: .utf8)
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
