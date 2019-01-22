import Foundation

protocol BacktraceClientType {
    func send() throws -> BacktraceResult
    func handlePendingCrashes() throws
}
