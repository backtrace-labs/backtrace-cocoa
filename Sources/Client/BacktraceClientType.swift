import Foundation

protocol BacktraceClientType {
    func send(exception: NSException?) throws -> BacktraceResult
    func handlePendingCrashes() throws
}
