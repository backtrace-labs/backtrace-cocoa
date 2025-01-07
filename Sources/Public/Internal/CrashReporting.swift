import Foundation

protocol CrashReporting {
    func generateLiveReport(exception: NSException?, attributes: Attributes,
                            attachmentPaths: [String]) throws -> BacktraceReport
    func pendingCrashReport() async throws -> BacktraceReport
    func purgePendingCrashReport() async throws
    func hasPendingCrashes() -> Bool
    func enableCrashReporting() throws
    func signalContext(_ mutableContext: inout SignalContext)
    func setCustomData(data: Data) -> Void
}
