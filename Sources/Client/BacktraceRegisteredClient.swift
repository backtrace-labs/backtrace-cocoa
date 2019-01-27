import Foundation

class BacktraceRegisteredClient {

    private let reporter: CrashReporting
    private var networkClient: NetworkClientType
    private let repository: PersistentRepository<BacktraceCrashReport>
    private let watcher: BacktraceWatcher<PersistentRepository<BacktraceCrashReport>>
    
    init(reporter: CrashReporting = CrashReporter(),
         networkClient: NetworkClientType,
         dbSettings: BacktraceDatabaseSettings) throws {
        self.reporter = reporter
        self.networkClient = networkClient
        self.repository = try PersistentRepository<BacktraceCrashReport>(settings: dbSettings)
        self.watcher = try BacktraceWatcher(settings: dbSettings, networkClient: networkClient, repository: repository)
    }
}

extension BacktraceRegisteredClient: BacktraceClientType {

    func handlePendingCrashes() throws {
        try reporter.enableCrashReporting()
        guard reporter.hasPendingCrashes() else {
            BacktraceLogger.debug("No pending crashes")
            return
        }
        let resource = try reporter.pendingCrashReport()
        _ = try send(resource)
        try reporter.purgePendingCrashReport()
    }

    func send(_ exception: NSException? = nil) throws -> BacktraceResult {
        let resource: BacktraceCrashReport
        if let exception = exception {
            resource = try reporter.generateLiveReport(exception: exception)
        } else {
            resource = try reporter.generateLiveReport()
        }
        return try send(resource)
    }
    
    private func send(_ resource: BacktraceCrashReport) throws -> BacktraceResult {
        do {
            let result = try networkClient.send(resource.reportData)
            return result.backtraceResult
        } catch let error as BacktraceErrorResponse {
            try repository.save(resource)
            throw error
        }
    }
}
