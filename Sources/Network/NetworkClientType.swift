import Foundation

protocol NetworkClientType {
    var successfulSendTimestamps: [TimeInterval] { get set }
    func send(_ report: BacktraceCrashReport) throws -> BacktraceResult
    var delegate: BacktraceClientDelegate? { get set }
}
