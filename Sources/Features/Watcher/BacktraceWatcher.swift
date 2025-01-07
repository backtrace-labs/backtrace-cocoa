import Foundation

final class BacktraceWatcher<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceReport {

    let settings: BacktraceDatabaseSettings
    let credentials: BacktraceCredentials
    let networkClient: BacktraceNetworkClient
    let repository: BacktraceRepository
    var timer: DispatchSourceTimer?
    let queue: DispatchQueue
    private let state = WatcherStateActor()

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
        configureTimer(with: DispatchWorkItem {
            Task {
                await self.timerEventHandler()
            }
        })
    }

    internal func batchRetry() async {
        guard networkClient.isNetworkAvailable() else { return }
        guard let reports = try? await reportsFromRepository(limit: 10), !reports.isEmpty else { return }
        await BacktraceLogger.debug("Resending reporting. Batch size: \(reports.count)")

        for report in reports {
        do {
            let request = try await MultipartRequest(configuration: credentials.configuration, report: report).request
            let result = try await networkClient.send(request: request)
            guard !result.isSuccess else {
                try await repository.delete(report)
                continue
            }
            try await repository.incrementRetryCount(report, limit: settings.retryLimit)
            } catch let error as NetworkError {
                await BacktraceLogger.error(error)
                // network connection error - do nothing.
            } catch {
                await BacktraceLogger.error(error)
                try? await repository.incrementRetryCount(report, limit: settings.retryLimit)
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

    internal func timerEventHandler() async {
        self.timer?.suspend()
        defer { self.timer?.resume() }
        await self.batchRetry()
    }

    internal func resetTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

// MARK: - Reports retrieving
extension BacktraceWatcher {

    // Takes from `repository` reports to send
    internal func reportsFromRepository(limit: Int) async throws -> [BacktraceRepository.Resource] {
        switch settings.retryOrder {
        case .queue: return try await repository.getOldest(count: limit)
        case .stack: return try await repository.getLatest(count: limit)
        }
    }
}

// MARK: - Actor for State Management
actor WatcherStateActor {
    var timer: DispatchSourceTimer?

    func setTimer(_ newTimer: DispatchSourceTimer) {
        timer = newTimer
    }

    func suspendTimer() {
        timer?.suspend()
    }

    func resumeTimer() {
        timer?.resume()
    }

    func cancelTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}
