import Foundation

final class BacktraceMetricsContainer {

    private var uniqueEvents = [UniqueEvent]()
    private var summedEvents = [SummedEvent]()
    private let lock = NSLock()

    static let startupSummedEventName = "Application Launches"
    static let startupUniqueEventName = "guid"

    var count: Int {
        return lock.withLock { uniqueEvents.count + summedEvents.count }
    }

    init(settings: BacktraceMetricsSettings) {
        self.add(event: SummedEvent(name: BacktraceMetricsContainer.startupSummedEventName))
        self.add(event: UniqueEvent(name: BacktraceMetricsContainer.startupUniqueEventName))
    }

    func add(event: UniqueEvent) {
        lock.withLock { uniqueEvents.append(event) }
    }

    func add(event: SummedEvent) {
        lock.withLock { summedEvents.append(event) }
    }

    func getSummedEventsPayload() -> SummedEventsPayload {
        return lock.withLock { SummedEventsPayload(events: summedEvents) }
    }

    func getUniqueEventsPayload() -> UniqueEventsPayload {
        return lock.withLock { UniqueEventsPayload(events: uniqueEvents) }
    }

    func clearSummedEvents() {
        lock.withLock { summedEvents.removeAll() }
    }
}

extension BacktraceMetricsContainer: @unchecked Sendable {}
