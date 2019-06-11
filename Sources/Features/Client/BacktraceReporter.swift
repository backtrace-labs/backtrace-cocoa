import Foundation

final class BacktraceReporter {

    private let reporter: CrashReporting
    private var api: BacktraceApiProtocol
    private let repository: PersistentRepository<BacktraceReport>
    private let watcher: BacktraceWatcher<PersistentRepository<BacktraceReport>>
    private var attributesProvider: SignalContext
    
    init(reporter: CrashReporting, api: BacktraceApiProtocol,
         dbSettings: BacktraceDatabaseSettings, reportsPerMin: Int) throws {
        self.reporter = reporter
        self.api = api
        self.repository = try PersistentRepository<BacktraceReport>(settings: dbSettings)
        self.watcher = try BacktraceWatcher(settings: dbSettings,
                                            reportsPerMin: reportsPerMin,
                                            api: api,
                                            repository: repository)
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
            BacktraceLogger.debug("No pending crashes")
            return
        }
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
        do {
            let result = try api.send(resource)
            if result.backtraceStatus != .ok, let report = result.report {
                try repository.save(report)
            }
            return result
        } catch let error as BacktraceErrorResponse {
            try repository.save(resource)
            throw error
        }
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
