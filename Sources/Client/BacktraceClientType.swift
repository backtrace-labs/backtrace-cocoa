
import Foundation

protocol BacktraceClientType {
    func send(_ error: Error) throws -> BacktraceResult
    func send(exception: NSException) throws -> BacktraceResult
    func handlePendingCrashes() throws
}
