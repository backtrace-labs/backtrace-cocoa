import Foundation

protocol BacktraceApiProtocol {
    func send(_ report: BacktraceReport) async throws -> BacktraceResult
    var delegate: BacktraceClientDelegate? { get set }
}

protocol BacktraceMetricsApiProtocol {
    func sendMetrics(_ payload: SummedEventsPayload, url: URL) async
    func sendMetrics(_ payload: UniqueEventsPayload, url: URL) async
}
