import Foundation

@objc open class BacktraceMetrics : NSObject {
    
    @objc public var uniqueEventsDelegate: BacktraceMetricsDelegate?
    @objc public var summedEventsDelegate: BacktraceMetricsDelegate?
    
    private var uniqueEvents = [UniqueEvent]()
    private var summedEvents = [SummedEvent]()
    
    init(api: BacktraceApi,
         settings: BacktraceMetricsSettings,
         credentials: BacktraceCredentials,
         urlSession: URLSession = URLSession(configuration: .ephemeral)) {
    }
    
    @objc public func enable() {
        
    }
    
    @objc public func addUniqueEvent(name: String) {
        var event = UniqueEvent(name: name)
        
    }
    
    @objc public func addSummedEvent(name: String) {
        var event = SummedEvent(name: name)

    }
}
