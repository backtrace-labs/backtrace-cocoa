import Foundation

final class BacktraceWatcher<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceReport {

    let settings: BacktraceDatabaseSettings
    let credentials: BacktraceCredentials
    let networkClient: BacktraceNetworkClient
    let repository: BacktraceRepository
    var timer: DispatchSourceTimer?
    let queue: DispatchQueue

    init(settings: BacktraceDatabaseSettings,
         networkClient: BacktraceNetworkClient,
         credentials: BacktraceCredentials,
         repository: BacktraceRepository,
         dispatchQueue: DispatchQueue = DispatchQueue(label: "backtrace.timer", qos: .background)) {

        self.settings = settings
        self.repository = repository
        self.networkClient = networkClient
        self.queue = dispatchQueue
        self.credentials = credentials
    }

    func enable() {
        guard settings.retryBehaviour == .interval else { return }
        configureTimer(with: DispatchWorkItem(block: timerEventHandler))
    }

    internal func batchRetry() {
        guard networkClient.isNetworkAvailable() else { return }
        guard let reports = try? reportsFromRepository(limit: 10), !reports.isEmpty else { return }
        BacktraceLogger.debug("Resending reporting. Batch size: \(reports.count)")

        for report in reports {
        do {
            let request = try MultipartRequest(configuration: credentials.configuration, report: report).request
            let result = try networkClient.send(request: request)
            guard !result.isSuccess else {
                try repository.delete(report)
                continue
            }
            try repository.incrementRetryCount(report, limit: settings.retryLimit)
            } catch let error as NetworkError {
                BacktraceLogger.error(error)
                // network connection error - do nothing.
            } catch {
                BacktraceLogger.error(error)
                try? repository.incrementRetryCount(report, limit: settings.retryLimit)
            }
        }
    }

    deinit {
        resetTimer()
    }
}

// MARK: - Timer
extension BacktraceWatcher {

    internal func configureTimer(with handler: DispatchWorkItem) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        self.timer = timer
        let repeating: DispatchTimeInterval = .seconds(settings.retryInterval)
        timer.schedule(deadline: DispatchTime.now() + repeating, repeating: repeating)
        timer.setEventHandler(handler: handler)
        timer.resume()
    }

    internal func timerEventHandler() {
        self.timer?.suspend()
        defer { self.timer?.resume() }
        self.batchRetry()
    }

    internal func resetTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

// MARK: - Reports retrieving
extension BacktraceWatcher {

    // Takes from `repository` reports to send
    internal func reportsFromRepository(limit: Int) throws -> [BacktraceRepository.Resource] {
        switch settings.retryOrder {
        case .queue: return try repository.getOldest(count: limit)
        case .stack: return try repository.getLatest(count: limit)
        }
    }
}
