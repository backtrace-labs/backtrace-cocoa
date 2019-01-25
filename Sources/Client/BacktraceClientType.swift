import Foundation

protocol BacktraceClientType {
    func send(_ exception: NSException?) throws -> BacktraceResult
    func handlePendingCrashes() throws
}
