import Foundation

final class BacktraceMetricsContainer {
    
    private var uniqueEvents = [UniqueEvent]()
    private var summedEvents = [SummedEvent]()
    
    private let settings: BacktraceMetricsSettings
    
    init(settings: BacktraceMetricsSettings) {
        self.settings = settings
    }
    
    func add(event: UniqueEvent) {
        uniqueEvents.append(event)
    }
    
    func add(event: SummedEvent) {
        summedEvents.append(event)
    }
}
