import Foundation

protocol NetworkClientType {
    @discardableResult
    func send(_ report: Data) throws -> BacktraceResponse
}

protocol NetworkClientDelegate {
    func beforeSend()
    func afterSend()
    func requestHandler()
    func onServerResponse()
    func onServerError()
}
