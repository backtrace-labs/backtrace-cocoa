import Foundation

protocol BacktraceApiProtocol {
    var successfulSendTimestamps: [TimeInterval] { get set }
    func send(_ report: BacktraceReport) throws -> BacktraceResult
    var delegate: BacktraceClientDelegate? { get set }
}
