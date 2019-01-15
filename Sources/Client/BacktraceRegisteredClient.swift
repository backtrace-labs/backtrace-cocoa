//
//  BacktraceRegisteredClient.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 06/01/2019.
//

import Foundation

class BacktraceRegisteredClient {

    private let reporter: CrashReporting
    private var networkClient: NetworkClientType
    private let repository = InMemoryRepository<CrashModel>()

    init(reporter: CrashReporting = CrashReporter(), networkClient: NetworkClientType) {
        self.reporter = reporter
        self.networkClient = networkClient
    }
}

extension BacktraceRegisteredClient: BacktraceClientType {
    func send(exception: NSException) throws {
        let resource = try reporter.generateLiveReport()
        try repository.save(resource)
        try networkClient.send(resource.reportData)
        try repository.delete(resource)
    }

    func handlePendingCrashes() throws {
        try reporter.enableCrashReporting()
        guard reporter.hasPendingCrashes() else {
            Logger.debug("No pending crashes")
            return
        }
        let resource = try reporter.pendingCrashReport()
        try repository.save(resource)
        try networkClient.send(resource.reportData)
        try repository.delete(resource)
        try reporter.purgePendingCrashReport()
    }

    func send(_ error: Error) throws {
        let resource = try reporter.generateLiveReport()
        try repository.save(resource)
        try networkClient.send(resource.reportData)
        try repository.delete(resource)
    }
}
