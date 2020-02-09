import Foundation

final class BacktraceReporter {
    
    private let reporter: CrashReporting
    private var api: BacktraceApi
    private let watcher: BacktraceWatcher<PersistentRepository<BacktraceReport>>
    private var attributesProvider: SignalContext
    
    init(reporter: CrashReporting,
         api: BacktraceApi,
         dbSettings: BacktraceDatabaseSettings,
         credentials: BacktraceCredentials) throws {
        self.reporter = reporter
        self.api = api
        self.watcher =
            BacktraceWatcher(settings: dbSettings,
                             networkClient: BacktraceNetworkClient(urlSession: URLSession(configuration: .ephemeral)),
                             credentials: credentials,
                             repository: try PersistentRepository<BacktraceReport>(settings: dbSettings))
        self.attributesProvider = AttributesProvider()
        self.reporter.signalContext(&attributesProvider)
    }
}

extension BacktraceReporter {
    
    func enableCrashReporter() throws {
        try reporter.enableCrashReporting()
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
        _ = try send(resource: resource)
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
    func send(resource: BacktraceReport) throws -> BacktraceResult {
        return try api.send(resource)
    }
    
    func send(exception: NSException? = nil, attachmentPaths: [String] = [],
              faultMessage: String? = nil) throws -> BacktraceResult {
        attributesProvider.set(faultMessage: faultMessage)
        let resource = try reporter.generateLiveReport(exception: exception,
                                                       attributes: attributesProvider.allAttributes,
                                                       attachmentPaths: attachmentPaths)
        return try send(resource: resource)
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
