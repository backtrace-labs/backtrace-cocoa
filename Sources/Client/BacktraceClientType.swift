//
//  BacktraceClientType.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 06/01/2019.
//

import Foundation

protocol BacktraceClientType {
    func send(_ error: Error) throws
    func send(exception: NSException) throws
    func handlePendingCrashes() throws
}
