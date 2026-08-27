import Foundation

final class BacktraceMetricsContainer {

    private var uniqueEvents = [UniqueEvent]()
    private var summedEvents = [SummedEvent]()
    private let lock = NSLock()

    static let startupSummedEventName = "Application Launches"
    static let startupUniqueEventName = "guid"

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return uniqueEvents.count + summedEvents.count
    }

    init(settings: BacktraceMetricsSettings) {
        self.add(event: SummedEvent(name: BacktraceMetricsContainer.startupSummedEventName))
        self.add(event: UniqueEvent(name: BacktraceMetricsContainer.startupUniqueEventName))
    }

    func add(event: UniqueEvent) {
        lock.lock()
        defer { lock.unlock() }
        uniqueEvents.append(event)
    }

    func add(event: SummedEvent) {
        lock.lock()
        defer { lock.unlock() }
        summedEvents.append(event)
    }

    func getSummedEventsPayload() -> SummedEventsPayload {
        lock.lock()
        defer { lock.unlock() }
        return SummedEventsPayload(events: summedEvents)
    }

    func getUniqueEventsPayload() -> UniqueEventsPayload {
        lock.lock()
        defer { lock.unlock() }
        return UniqueEventsPayload(events: uniqueEvents)
    }

    func clearSummedEvents() {
        lock.lock()
        defer { lock.unlock() }
        summedEvents.removeAll()
    }
}
