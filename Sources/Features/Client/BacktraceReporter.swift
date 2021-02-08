import Foundation

final class BacktraceReporter {
    
    let reporter: CrashReporting
    private(set) var api: BacktraceApi
    private let watcher: BacktraceWatcher<PersistentRepository<BacktraceReport>>
    private(set) var attributesProvider: SignalContext
    private(set) var backtraceOomWatcher: BacktraceOomWatcher
    let repository: PersistentRepository<BacktraceReport>
    
    init(reporter: CrashReporting,
         api: BacktraceApi,
         dbSettings: BacktraceDatabaseSettings,
         credentials: BacktraceCredentials,
         urlSession: URLSession = URLSession(configuration: .ephemeral)) throws {
        self.reporter = reporter
        self.api = api
        self.watcher =
            BacktraceWatcher(settings: dbSettings,
                             networkClient: BacktraceNetworkClient(urlSession: urlSession),
                             credentials: credentials,
                             repository: try PersistentRepository<BacktraceReport>(settings: dbSettings))
        self.repository = try PersistentRepository<BacktraceReport>(settings: dbSettings)
        let localAttributeProvider = AttributesProvider()
        self.attributesProvider = localAttributeProvider
        self.backtraceOomWatcher = BacktraceOomWatcher(repository: self.repository, crashReporter: self.reporter, attributes: localAttributeProvider, backtraceApi: self.api)
        self.reporter.signalContext(&attributesProvider)
    }
}

extension BacktraceReporter {
    
    func enableCrashReporter() throws {
        try reporter.enableCrashReporting()
        watcher.enable()
    }
    
    func handlePendingCrashes() throws {
        // always try to remove pending crash report from disk
        defer { try? reporter.purgePendingCrashReport() }
        
        // try to send pending crash report
        guard reporter.hasPendingCrashes() else {
            BacktraceLogger.debug("There are no pending crash crashes to send.")
            return
        }
        BacktraceLogger.debug("There is a pending crash report to send.")
        let resource = try reporter.pendingCrashReport()
        _ = send(resource: resource)
    }
}

extension BacktraceReporter: BacktraceClientCustomizing {
    var delegate: BacktraceClientDelegate? {
        get {
            return api.delegate
        }
        set {
            api.delegate = newValue
        }
    }
    
    var attributes: Attributes {
        get {
            return attributesProvider.attributes
        } set {
            attributesProvider.attributes = newValue
        }
    }
}

extension BacktraceReporter {
    func send(resource: BacktraceReport) -> BacktraceResult {
        do {
            return try api.send(resource)
        } catch {
            BacktraceLogger.error(error)
            try? repository.save(resource)
            return BacktraceResult(error.backtraceStatus)
        }
    }
    
    func send(exception: NSException? = nil, attachmentPaths: [String] = [],
              faultMessage: String? = nil) throws -> BacktraceResult {
        attributesProvider.set(faultMessage: faultMessage)
        let resource = try reporter.generateLiveReport(exception: exception,
                                                       attributes: attributesProvider.allAttributes,
                                                       attachmentPaths: attachmentPaths)
        return send(resource: resource)
    }
    
    func generate(exception: NSException? = nil, attachmentPaths: [String] = [],
                  faultMessage: String? = nil) throws -> BacktraceReport {
        attributesProvider.set(faultMessage: faultMessage)
        let resource = try reporter.generateLiveReport(exception: exception,
                                                       attributes: attributesProvider.allAttributes,
                                                       attachmentPaths: attachmentPaths)
        return resource
    }
}


//// Provides notification interfaces for BacktraceOOMWatcher and Breadcrumbs support
extension BacktraceReporter {
    internal func enableOomWatcher() {
        self.backtraceOomWatcher.start()
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(applicationWillEnterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(didEnterBackgroundNotification),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(handleTermination),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector:#selector(handleLowMemoryWarning),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
    }
    
    @objc private func applicationWillEnterForeground(_ notification: NSNotification) {
        self.backtraceOomWatcher.applicationWillEnterForeground()
    }
    
    
    @objc private func didEnterBackgroundNotification(_ notification: NSNotification) {
        self.backtraceOomWatcher.didEnterBackgroundNotification()
    }
    
    @objc func handleTermination() {
        self.backtraceOomWatcher.handleTermination()
    }
    @objc func handleLowMemoryWarning() {
        self.backtraceOomWatcher.handleLowMemoryWarning()
    }
}
