import Foundation

class BacktraceUnregisteredClient: BacktraceClientType {
    private static let printBlock = { () -> BacktraceResult in
        BacktraceLogger.error("Backtrace client is not regiestered.")
        return BacktraceResult(.notRegisterd)
    }
    
    func handlePendingCrashes() throws {
        _ = BacktraceUnregisteredClient.printBlock()
    }

    func send(exception: NSException?) throws -> BacktraceResult {
        return BacktraceUnregisteredClient.printBlock()
    }
}
