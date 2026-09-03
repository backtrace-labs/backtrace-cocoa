import Foundation

@objc open class BacktraceMetrics: NSObject {

    private let api: BacktraceApi
    private let senderQueue: DispatchQueue?

    private var backtraceMetricsSender: BacktraceMetricsSender?

    private var backtraceMetricsContainer: BacktraceMetricsContainer?
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false

    @objc public var count: Int {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !shutdownRequested else { return 0 }
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.warning("Count method called but metrics is not enabled")
            return 0
        }
        return containerUnwrapped.count
    }

    init(api: BacktraceApi,
         senderQueue: DispatchQueue? = nil) {
        self.api = api
        self.senderQueue = senderQueue
        super.init()
    }

    @objc public func enable(settings: BacktraceMetricsSettings) {
        lifecycleLock.lock()
        guard !shutdownRequested else {
            lifecycleLock.unlock()
            return
        }
        let previousSender = backtraceMetricsSender
        let container = BacktraceMetricsContainer(settings: settings)
        let sender = BacktraceMetricsSender(api: api,
                                            metricsContainer: container,
                                            settings: settings,
                                            senderQueue: senderQueue)
        backtraceMetricsContainer = container
        backtraceMetricsSender = sender
        lifecycleLock.unlock()

        // `enable` replaces the metrics session.
        // Stop a queued startup send from the previous session before starting its replacement.
        previousSender?.shutdown()
        sender.enable()
    }

    @objc public func addUniqueEvent(name: String) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !shutdownRequested else { return }
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not add metrics event, metrics is not initialized")
            return
        }
        containerUnwrapped.add(event: UniqueEvent(name: name))
    }

    @objc public func addSummedEvent(name: String) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !shutdownRequested else { return }
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not add metrics event, metrics is not initialized")
            return
        }
        containerUnwrapped.add(event: SummedEvent(name: name))
    }
    
    @objc public func clearSummedEvents() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !shutdownRequested else { return }
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not clear metrics event, metrics is not initialized")
            return
        }
        containerUnwrapped.clearSummedEvents()
    }
    
    @objc public func getSummedEvents() -> [Any] {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !shutdownRequested else { return [] }
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not get Summed events, metrics is not initialized")
            return []
        }
        
        let payload = containerUnwrapped.getSummedEventsPayload()
        return payload.events as [SummedEvent]
    }
    
    @objc public func getUniqueEvents() -> [Any] {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !shutdownRequested else { return [] }
        guard let containerUnwrapped = backtraceMetricsContainer else {
            BacktraceLogger.error("Could not get Unique events, metrics is not initialized")
            return []
        }
        
        let payload = containerUnwrapped.getUniqueEventsPayload()
        return payload.events as [UniqueEvent]
    }

    internal var isShutdown: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }

    /// Permanently disables this metrics facade for a retained native-bridge client.
    /// The public Cocoa API remains restartable for clients that have not used this hook.
    internal func shutdownForNativeBridge() {
        lifecycleLock.lock()
        guard !shutdownRequested else {
            lifecycleLock.unlock()
            return
        }
        shutdownRequested = true
        let sender = backtraceMetricsSender
        lifecycleLock.unlock()
        sender?.shutdown()
    }
    
}
