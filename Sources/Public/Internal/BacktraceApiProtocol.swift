import Foundation

protocol BacktraceApiProtocol: Sendable {
    func send(_ report: BacktraceReport) throws -> BacktraceResult
    var delegate: BacktraceClientDelegate? { get set }
}

protocol BacktraceMetricsApiProtocol: Sendable {
    func sendMetrics(_ payload: SummedEventsPayload, url: URL)
    func sendMetrics(_ payload: UniqueEventsPayload, url: URL)
}
