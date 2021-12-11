import Foundation

protocol BacktraceApiProtocol {
    func send(_ report: BacktraceReport) throws -> BacktraceResult
    var delegate: BacktraceClientDelegate? { get set }
}

protocol BacktraceMetricsApiProtocol {
    func sendMetrics(_ payload: SummedEventsPayload, url: URL) throws
    func sendMetrics(_ payload: UniqueEventsPayload, url: URL) throws
    var summedEventsDelegate: BacktraceMetricsDelegate? { get set }
    var uniqueEventsDelegate: BacktraceMetricsDelegate? { get set }
}
