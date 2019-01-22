import Foundation

protocol BacktraceClientType {
    func send() throws -> BacktraceResult
    func send(exception: NSException) throws -> BacktraceResult
    func handlePendingCrashes() throws
}
