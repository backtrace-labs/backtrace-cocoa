//
//  BacktraceUnregisteredClient.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 06/01/2019.
//

import Foundation

class BacktraceUnregisteredClient: BacktraceClientType {
    private static let printBlock = {
        Logger.error("Backtrace client is not regiestered.")
    }

    func handlePendingCrashes() throws {
        BacktraceUnregisteredClient.printBlock()
    }

    func generateLiveReport() -> String {
        BacktraceUnregisteredClient.printBlock()
        return ""
    }

    func send(_ error: Error) throws {
        BacktraceUnregisteredClient.printBlock()
    }
}

extension BacktraceUnregisteredClient: BacktraceClientTypeDebuggable {
    var pendingCrashReport: String? {
        BacktraceUnregisteredClient.printBlock()
        return nil
    }
}
