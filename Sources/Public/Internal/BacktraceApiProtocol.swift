import Foundation

protocol BacktraceApiProtocol {
    func send(_ report: BacktraceReport) throws -> BacktraceResult
    func sendMetrics(_ metrics: Payload<Event>) throws -> BacktraceMetricsResult
    var delegate: BacktraceClientDelegate? { get set }
    var summedEventsDelegate: BacktraceMetricsDelegate? { get set }
    var uniqueEventsDelegate: BacktraceMetricsDelegate? { get set }
}
