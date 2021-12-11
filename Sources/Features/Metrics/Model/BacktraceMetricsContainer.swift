import Foundation

final class BacktraceMetricsContainer {
    
    private var uniqueEvents = [UniqueEvent]()
    private var summedEvents = [SummedEvent]()
    
    private let settings: BacktraceMetricsSettings
    
    static let startupSummedEventName = "Application Launches"
    
    var count: Int {
        get {
            return uniqueEvents.count + summedEvents.count
        }
    }
    
    init(settings: BacktraceMetricsSettings) {
        self.settings = settings
        self.add(event: SummedEvent(name: BacktraceMetricsContainer.startupSummedEventName))
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
}
