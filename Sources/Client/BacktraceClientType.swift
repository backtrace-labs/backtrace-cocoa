import Foundation

protocol BacktraceClientType {
    func send(_ exception: NSException?, _ attributes: [String: Any]) throws -> BacktraceResult
    func handlePendingCrashes() throws
}
