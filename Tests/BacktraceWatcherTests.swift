import Foundation
import Testing

@testable import Backtrace

@Suite struct BacktraceWatcherTests {
    // swiftlint:disable function_body_length

    private static func backtraceReport(for attributes: Attributes) throws -> BacktraceReport {
        let crashReporter = BacktraceCrashReporter()
        return try crashReporter.generateLiveReport(attributes: attributes)
    }

    // MARK: - Given default values

    @Test("sets the timer")
    func setsTheTimer() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        #expect(watcher.settings === dbSettings)
        #expect(watcher.credentials === credentials)
        #expect(watcher.networkClient === networkClient)
        #expect(watcher.repository === repository)
        #expect(watcher.timer == nil)
    }

    @Test("does not configure a timer when retry behaviour is disabled")
    func disabledRetryDoesNotConfigureTimer() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        dbSettings.retryBehaviour = .none
        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        #expect(watcher.timer == nil)
    }

    // MARK: - Given enabled retry behaviour

    @Test("fires timer when retry behaviour is interval")
    func enabledRetryFiresTimer() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        dbSettings.retryBehaviour = .interval
        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.resetTimer()
        watcher.enable()
        #expect(watcher.timer != nil)
    }

    // MARK: - Accessing resources: one element

    @Test("accessing resources with one element completes successfully")
    func accessingResourcesOneElement() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

        #expect(throws: Never.self) { try watcher.reportsFromRepository(limit: 1) }
    }

    // MARK: - Accessing resources: queue order

    @Test("queue order gets the oldest element")
    func queueOrderGetsOldestElement() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        dbSettings.retryOrder = .queue
        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        let firstReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
        try repository.save(firstReport)
        let secondReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2])
        try repository.save(secondReport)
        let thirdReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 3])
        try repository.save(thirdReport)

        let reports = try watcher.reportsFromRepository(limit: 2)
        #expect(reports.count == 2)
        #expect(!reports.contains(firstReport))
        #expect(reports.contains(secondReport))
        #expect(reports.contains(thirdReport))
    }

    // MARK: - Accessing resources: stack order

    @Test("stack order gets latest element")
    func stackOrderGetsLatestElement() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        dbSettings.retryOrder = .stack
        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        let firstReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
        try repository.save(firstReport)
        let secondReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2])
        try repository.save(secondReport)
        let thirdReport = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 3])
        try repository.save(thirdReport)

        let reports = try watcher.reportsFromRepository(limit: 2)

        #expect(reports.count == 2)
        #expect(!reports.contains(thirdReport))
        #expect(reports.contains(firstReport))
        #expect(reports.contains(secondReport))
    }

    // MARK: - Batch retry: one element

    @Test("batch retry with one element clears pending reports")
    func batchRetryOneElementClearsPendingReports() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse(url: URL(string: "https://yourteam.backtrace.io")!)
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

        #expect(throws: Never.self) { watcher.batchRetry() }

        #expect(try watcher.repository.countResources() == 0)
    }

    // MARK: - Batch retry: two elements

    @Test("batch retry with two elements removes them from repository")
    func batchRetryTwoElementsRemovesFromRepository() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse(url: URL(string: "https://yourteam.backtrace.io")!)
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2]))
        watcher.batchRetry()

        #expect(try watcher.repository.countResources() == 0)
    }

    // MARK: - Batch retry: connection error

    @Test("batch retry with connection error does not modify the database")
    func batchRetryConnectionErrorDoesNotModifyDatabase() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = MockConnectionErrorResponse(url: URL(string: "https://yourteam.backtrace.io")!)
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

        watcher.batchRetry()
        #expect(try watcher.repository.countResources() == 1)
    }

    // MARK: - Batch retry: limit reached

    @Test("batch retry with limit reached removes the report from database")
    func batchRetryLimitReachedRemovesReport() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = Mock403Response(url: URL(string: "https://yourteam.backtrace.io")!)
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

        watcher.batchRetry()
        #expect(try watcher.repository.countResources() == 1)
    }

    // MARK: - Batch retry: increments retry counter

    @Test("batch retry increments retry counter")
    func batchRetryIncrementsRetryCounter() throws {
        let dbSettings = BacktraceDatabaseSettings()
        let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
        let repository = WatcherRepositoryMock()
        let urlSession = URLSessionMock()
        urlSession.response = Mock403Response(url: URL(string: "https://yourteam.backtrace.io")!)
        let networkClient = BacktraceNetworkClient(urlSession: urlSession)

        try repository.clear()

        let watcher = BacktraceWatcher(settings: dbSettings,
                                        networkClient: networkClient,
                                        credentials: credentials,
                                        repository: repository)
        watcher.enable()
        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
        try repository.save(report)

        #expect(watcher.repository.retryCount(for: report) == 0)
        watcher.batchRetry()
        #expect(watcher.repository.retryCount(for: report) == 1)
    }

    // swiftlint:enable function_body_length
}
