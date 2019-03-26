import Foundation

protocol CrashReporting {
    func generateLiveReport(exception: NSException?, attributes: Attributes,
                            attachmentPaths: [String]) throws -> BacktraceReport
    func pendingCrashReport() throws -> BacktraceReport
    func purgePendingCrashReport() throws
    func hasPendingCrashes() -> Bool
    func enableCrashReporting() throws
    func signalContext(_ mutableContext: inout SignalContext)
}
