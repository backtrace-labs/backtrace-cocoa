import Foundation

class BacktraceRegisteredClient {

    private let reporter: CrashReporting
    private var networkClient: NetworkClientType
    private let repository = InMemoryRepository<BacktraceCrashReport>()

    init(reporter: CrashReporting = CrashReporter(), networkClient: NetworkClientType) {
        self.reporter = reporter
        self.networkClient = networkClient
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
        try repository.save(resource)
        try networkClient.send(resource.reportData)
        try repository.delete(resource)
        try reporter.purgePendingCrashReport()
    }

    func send(_ exception: NSException? = nil) throws -> BacktraceResult {
        let resource: BacktraceCrashReport
        if let exception = exception {
            resource = try reporter.generateLiveReport(exception: exception)
        } else {
            resource = try reporter.generateLiveReport()
        }
        try repository.save(resource)
        let result = try networkClient.send(resource.reportData)
        try repository.delete(resource)
        return result.backtraceResult
    }
}
