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
    
    func send(exception: NSException) throws {
        BacktraceUnregisteredClient.printBlock()
    }

    func handlePendingCrashes() throws {
        BacktraceUnregisteredClient.printBlock()
    }

    func send(_ error: Error) throws {
        BacktraceUnregisteredClient.printBlock()
    }
}
