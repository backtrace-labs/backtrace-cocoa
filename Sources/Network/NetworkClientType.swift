import Foundation

protocol NetworkClientType {
    var successfulSendTimestamps: [TimeInterval] { get set }
    func send(_ report: BacktraceCrashReport, _ attributes: [String: Any]) throws -> BacktraceResult
    var delegate: BacktraceClientDelegate? { get set }
}
