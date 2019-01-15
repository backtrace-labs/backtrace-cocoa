//
//  BacktraceClientType.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 06/01/2019.
//

import Foundation

protocol BacktraceClientType {
    func send(_ error: Error) throws
}

protocol BacktraceClientTypeDebuggable {
    func generateLiveReport() -> String
    func handlePendingCrashes() throws
    var pendingCrashReport: String? { get }
}
