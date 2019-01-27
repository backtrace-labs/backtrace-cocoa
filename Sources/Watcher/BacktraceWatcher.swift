import Foundation

final class BacktraceWatcher<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceCrashReport {
    
    let settings: BacktraceDatabaseSettings
    let networkClient: NetworkClientType
    let repository: BacktraceRepository
    var timer: DispatchSourceTimer?
    let queue: DispatchQueue
    
    init(settings: BacktraceDatabaseSettings, networkClient: NetworkClientType,
         repository: BacktraceRepository,
         dispatchQueue: DispatchQueue = DispatchQueue(label: "backtrace.timer", qos: .background)) throws {
        self.settings = settings
        self.repository = repository
        self.networkClient = networkClient
        self.queue = dispatchQueue
        guard settings.retryBehaviour == .interval else { return }
        configureTimer()
    }
    
    private func configureTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        let repeating: DispatchTimeInterval = .seconds(settings.retryInterval)
        timer.schedule(deadline: DispatchTime.now() + repeating, repeating: repeating)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.timer?.suspend()
            defer { self.timer?.resume() }
            do {
                BacktraceLogger.debug("Retrying to send ")
                try self.batchRetry()
            } catch {
                BacktraceLogger.error(error)
            }
        }
        timer.resume()
    }
    
    private func getNextPendingCrash() throws -> BacktraceRepository.Resource? {
        if settings.retryOrder == .queue {
            return try repository.getLatest()
        }
        return try repository.getOldest()
    }
    
    private func batchRetry() throws {
        while let pendingCrashReport = try getNextPendingCrash() {
            do {
                try networkClient.send(pendingCrashReport.reportData)
                try repository.delete(pendingCrashReport)
            } catch {
                try repository.incrementRetryCount(pendingCrashReport, limit: settings.retryLimit)
            }
        }
    }
    
    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}
