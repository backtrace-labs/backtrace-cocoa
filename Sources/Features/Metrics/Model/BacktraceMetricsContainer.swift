import Foundation

final class BacktraceMetricsContainer {

    private var uniqueEvents = [UniqueEvent]()
    private var summedEvents = [SummedEvent]()

    private let settings: BacktraceMetricsSettings

    static let startupSummedEventName = "Application Launches"
    static let startupUniqueEventName = "guid"

    var count: Int {
        return uniqueEvents.count + summedEvents.count
    }

    init(settings: BacktraceMetricsSettings) {
        self.settings = settings
        self.add(event: SummedEvent(name: BacktraceMetricsContainer.startupSummedEventName))
        self.add(event: UniqueEvent(name: BacktraceMetricsContainer.startupUniqueEventName))
    }

    func add(event: UniqueEvent) {
        uniqueEvents.append(event)
    }

    func add(event: SummedEvent) {
        summedEvents.append(event)
    }

    func getSummedEventsPayload() -> SummedEventsPayload {
        return SummedEventsPayload(events: summedEvents)
    }

    func getUniqueEventsPayload() -> UniqueEventsPayload {
        return UniqueEventsPayload(events: uniqueEvents)
    }

    func clearSummedEvents() {
        summedEvents.removeAll()
    }
}
