import Foundation

@objc open class BacktraceMetrics: NSObject {

    private let api: BacktraceApi

    private var backtraceMetricsSender: BacktraceMetricsSender?

    private var backtraceMetricsContainer: BacktraceMetricsContainer?

    @objc public var count: Int {
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.warning("Count method called but metrics is not enabled")
            return 0
        }
        return containerUnwrapped.count
    }

    init(api: BacktraceApi) {
        self.api = api
        super.init()
    }

    @objc public func enable(settings: BacktraceMetricsSettings) {
        backtraceMetricsContainer = BacktraceMetricsContainer(settings: settings)
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not initialize Backtrace metrics sender")
            return
        }
        backtraceMetricsSender = BacktraceMetricsSender(api: api, metricsContainer: containerUnwrapped, settings: settings)
        guard let senderUnwrapped = backtraceMetricsSender else {
            BacktraceLogger.error("Could not initialize Backtrace metrics sender")
            return
        }
        senderUnwrapped.enable()
    }

    @objc public func addUniqueEvent(name: String) {
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not add metrics event, metrics is not initialized")
            return
        }
        containerUnwrapped.add(event: UniqueEvent(name: name))
    }

    @objc public func addSummedEvent(name: String) {
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not add metrics event, metrics is not initialized")
            return
        }
        containerUnwrapped.add(event: SummedEvent(name: name))
    }
    
    @objc public func clearSummedEvents() {
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not clear metrics event, metrics is not initialized")
            return
        }
        containerUnwrapped.clearSummedEvents()
    }
    
    @objc public func getSummedEvents() -> [Any] {
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not get Summed events, metrics is not initialized")
            return []
        }
        
        let payload = containerUnwrapped.getSummedEventsPayload()
        return payload.events as [SummedEvent]
    }
    
    @objc public func getUniqueEvents() -> [Any] {
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not get Unique events, metrics is not initialized")
            return []
        }
        
        let payload = containerUnwrapped.getUniqueEventsPayload()
        return payload.events as [UniqueEvent]
    }
    
}
