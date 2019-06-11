import Foundation

final class BacktraceWatcher<BacktraceRepository: Repository>
where BacktraceRepository.Resource == BacktraceReport {

    let settings: BacktraceDatabaseSettings
    let reportsPerMin: Int
    let api: BacktraceApiProtocol
    let repository: BacktraceRepository
    var timer: DispatchSourceTimer?
    let queue: DispatchQueue
    
    init(settings: BacktraceDatabaseSettings, reportsPerMin: Int, api: BacktraceApiProtocol,
         repository: BacktraceRepository,
         dispatchQueue: DispatchQueue = DispatchQueue(label: "backtrace.timer", qos: .background)) throws {
        self.settings = settings
        self.reportsPerMin = reportsPerMin
        self.repository = repository
        self.api = api
        self.queue = dispatchQueue
        guard settings.retryBehaviour == .interval else { return }
        configureTimer(with: DispatchWorkItem(block: timerEventHandler))
    }

    internal func batchRetry() throws {
        let reportsToSend = try limitedReportsToSend()
        if !reportsToSend.isEmpty {
            BacktraceLogger.debug("Resending reporting. Batch size: \(reportsToSend.count)")
        }
        
        for reportToSend in reportsToSend {
            do {
                let result = try api.send(reportToSend)
                if let reportData = result.report {
                    if result.backtraceStatus == .ok {
                        try repository.delete(reportData)
                    } else {
                        try repository.incrementRetryCount(reportData, limit: settings.retryLimit)
                    }
                } else {
                    try repository.incrementRetryCount(reportToSend, limit: settings.retryLimit)
                }
            } catch let error as HttpError {
                BacktraceLogger.error(error)
                // network connection error - do nothing.
            } catch {
                BacktraceLogger.error(error)
                try repository.incrementRetryCount(reportToSend, limit: settings.retryLimit)
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
        do {
            try self.batchRetry()
        } catch {
            BacktraceLogger.error(error)
        }
    }
    
    internal func resetTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

// MARK: - Reports retrieving
extension BacktraceWatcher {
    
    // Takes from `repository` reports to send
    internal func crashReportsFromRepository(limit: Int) throws -> [BacktraceRepository.Resource] {
        switch settings.retryOrder {
        case .queue: return try repository.getOldest(count: limit)
        case .stack: return try repository.getLatest(count: limit)
        }
    }
    
    internal func limitedReportsToSend() throws -> [BacktraceRepository.Resource] {
        // prepare set of reports to send, considering limits
        
        let currentTimestamp = Date().timeIntervalSince1970
        let numberOfSendsInLastOneMinute = api.successfulSendTimestamps
            .filter { currentTimestamp - $0 < 60.0 }.count
        let maxReportsToSend = max(0, abs(reportsPerMin - numberOfSendsInLastOneMinute))
        return try crashReportsFromRepository(limit: maxReportsToSend)
    }
}
