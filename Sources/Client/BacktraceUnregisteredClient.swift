import Foundation

class BacktraceUnregisteredClient: BacktraceClientType {
    private static let printBlock = { () -> BacktraceResult in
        BacktraceLogger.error("Backtrace client is not registered.")
        return BacktraceResult(.notRegistered, message: "Backtrace client is not registered.")
    }
    
    func handlePendingCrashes() throws {
        _ = BacktraceUnregisteredClient.printBlock()
    }

    func send(_ exception: NSException? = nil) throws -> BacktraceResult {
        return BacktraceUnregisteredClient.printBlock()
    }
}
