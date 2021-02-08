import Foundation

final class BacktraceOomWatcher {
    private var applicationState = [String :Any]()
    
    
    private(set) var lowMemoryFilePrefix = "_lowMemory"
    private(set) static var oomFilePath: URL? = getStatusFilePath()
    
    private(set) var statusFilePath: URL
    private(set) var crashReporter: CrashReporting
    private(set) var attributesProvider:AttributesProvider
    private(set) var backtraceApi: BacktraceApi
    private let repository: PersistentRepository<BacktraceReport>
    
    init(repository:  PersistentRepository<BacktraceReport>, crashReporter: CrashReporting, attributes: AttributesProvider, backtraceApi: BacktraceApi) {
        self.crashReporter = crashReporter
        self.attributesProvider = attributes
        self.backtraceApi = backtraceApi
        self.repository = repository
        
        // set default state
        self.applicationState["state"] = "foreground"
        self.applicationState["debugger"] = DebuggerChecker.isAttached()
        self.applicationState["appVersion"] = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String)
        self.applicationState["version"] = UIDevice.current.systemVersion
        
        // set status file url
        if(BacktraceOomWatcher.oomFilePath == nil) {
            // database path will point out sqlite database path
            // oom status should exist in the same directory where database exists.
            BacktraceOomWatcher.oomFilePath  = self.repository.url.deletingLastPathComponent().absoluteURL
                .appendingPathComponent("BacktraceOOMState")
        }
        self.statusFilePath = BacktraceOomWatcher.oomFilePath!
    }
    
    internal static func clean() {
        if((BacktraceOomWatcher.oomFilePath) != nil) {
            try! FileManager.default.removeItem(at: BacktraceOomWatcher.oomFilePath!)
        }
    }
    
    public func start() {
        sendPendingOomReports()
        // override previous application state after reading all information
        saveState()
    }
    
    internal static func getStatusFilePath() -> URL? {
        // oom status file is available in application cache dir - the same dir
        // where we store attributes
        
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cacheDir.appendingPathComponent("BacktraceOomState.plist")
    }
    
    private func sendPendingOomReports() {
        
        // if oom state file doesn't exist it means that we deleted it to
        // prevent sending false oom crashes
        if(!FileManager.default.fileExists(atPath: statusFilePath.path)){
            return
        }
        
        guard let backtraceOOMState = NSDictionary(contentsOf: statusFilePath) else {
            return
        }
        
        // no low memory warning
        if(backtraceOOMState["resource"] == nil) {
            return
        }
        
        // check if debugger was enabled
        if(backtraceOOMState["debugger"] as! Bool == true) {
            // detected system update
            return
        }
        // check system update
        if(backtraceOOMState["version"] as! String !=  UIDevice.current.systemVersion as String) {
            // detected system update
            return
        }
        
        // check application update
        if(backtraceOOMState["appVersion"] as! String != Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String ) {
            // detected app update
            return
        }
        
        var attributes = backtraceOOMState["resource.attributes"] as! Attributes
        attributes["error.message"] = "Out of memory detected."
        attributes["error.type"] = "Low Memory"
        attributes["state"] = backtraceOOMState["state"]
        
        // ok - we detected oom and we should report it
        guard let report = try? BacktraceReport(report: backtraceOOMState["resource"] as! Data, attributes: attributes,   attachmentPaths: []) else {
            return
        }
        
        do {
            let _ = try backtraceApi.send(report)
        } catch {
            BacktraceLogger.error(error)
            try? self.repository.save(report)
        }
        try! FileManager.default.removeItem(at: statusFilePath)
    }
}

extension BacktraceOomWatcher {
    func applicationWillEnterForeground() {
        self.applicationState["state"] = "foreground"
        saveState()
    }
    
    func didEnterBackgroundNotification() {
        self.applicationState["state"] = "background"
        saveState()
    }
    
    func handleTermination() {
        // application terminates correctly - for example: user decide to close app
        try! FileManager.default.removeItem(atPath: statusFilePath.path)
        NotificationCenter.default.removeObserver(self)
    }
    
    func handleLowMemoryWarning() {
        guard let resource = try? crashReporter.generateLiveReport(exception: nil,
                                                                   attributes: attributesProvider.allAttributes,
                                                                   attachmentPaths: []) else {
                                                                    return
        }
        
        applicationState["resource"] = resource.reportData
        applicationState["resource.attributes"] = resource.attributes
        saveState()
    }
    
    private func saveState() {
        guard (applicationState as NSDictionary).write(to: self.statusFilePath, atomically: true) else {
            return
        }
    }
}
