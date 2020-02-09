import Foundation

protocol BacktraceApiProtocol {
    func send(_ report: BacktraceReport) throws -> BacktraceResult
    var delegate: BacktraceClientDelegate? { get set }
}
