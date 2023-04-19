import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceWatcherTests: QuickSpec {
    // swiftlint:disable function_body_length
    override func spec() {
        describe("Watcher") {
            let dbSettings = BacktraceDatabaseSettings()
            let credentials = BacktraceCredentials(submissionUrl: URL(string: "https://yourteam.backtrace.io")!)
            let repository = WatcherRepositoryMock()
            let urlSession = URLSessionMock()
            urlSession.response = MockOkResponse()
            let networkClient = BacktraceNetworkClient(urlSession: urlSession)

            context("given default values") {

                throwingIt("sets the timer") {
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   networkClient: networkClient,
                                                   credentials: credentials,
                                                   repository: repository)
                    expect(watcher.settings).to(be(dbSettings))
                    expect(watcher.credentials).to(be(credentials))
                    expect(watcher.networkClient).to(be(networkClient))
                    expect(watcher.repository).to(be(repository))
                    expect(watcher.timer).to(beNil())
                }

                context("given disabled retry behaviour") {
                    throwingIt("does not configure a timer") {
                        dbSettings.retryBehaviour = .none
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       networkClient: networkClient,
                                                       credentials: credentials,
                                                       repository: repository)
                        expect(watcher.timer).to(beNil())
                    }
                }
            }

            context("given enabled retry behaviour") {
                throwingIt("fires timer") {
                    dbSettings.retryInterval = 1
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   networkClient: networkClient,
                                                   credentials: credentials,
                                                   repository: repository)
                    watcher.enable()
                    watcher.resetTimer()

                    waitUntil(timeout: .seconds(dbSettings.retryInterval + 1)) { (done) in
                        watcher.configureTimer(with: DispatchWorkItem(block: {
                            done()
                        }))
                    }
                }
            }

            describe("Accessing resources") {
                throwingBeforeEach { try repository.clear() }

                context("given one element") {
                    throwingIt("completes successfully") {
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       networkClient: networkClient,
                                                       credentials: credentials,
                                                       repository: repository)
                        watcher.enable()
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        expect { try watcher.reportsFromRepository(limit: 1) }.toNot(throwError())
                    }
                }

                context("given queue order") {
                    throwingIt("gets the oldest element") {
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
                        expect(reports.count).to(equal(2))
                        expect(reports).toNot(contain(firstReport))
                        expect(reports).to(contain(secondReport, thirdReport))
                    }
                }

                context("given stack order") {
                    throwingIt("gets latest element") {
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

                        expect(reports.count).to(equal(2))
                        expect(reports).toNot(contain(thirdReport))
                        expect(reports).to(contain(firstReport, secondReport))
                    }
                }
            }

            describe("Batch retry") {
                throwingBeforeEach {
                    try repository.clear()
                    urlSession.response = MockOkResponse(url: URL(string: "https://yourteam.backtrace.io")!)
                }

                context("given one element") {
                    throwingIt("clears pending reports") {
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       networkClient: networkClient,
                                                       credentials: credentials,
                                                       repository: repository)
                        watcher.enable()
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        expect { watcher.batchRetry() }.toNot(throwError())

                        expect(try watcher.repository.countResources()).to(equal(0))
                    }
                }

                context("given two elements") {
                    throwingIt("removes them from repository") {
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       networkClient: networkClient,
                                                       credentials: credentials,
                                                       repository: repository)
                        watcher.enable()
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2]))
                        watcher.batchRetry()

                        expect(try watcher.repository.countResources()).to(equal(0))
                    }
                }

                context("given connection error") {
                    throwingIt("does not modify the database") {
                        urlSession.response =
                            MockConnectionErrorResponse(url: URL(string: "https://yourteam.backtrace.io")!)
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       networkClient: networkClient,
                                                       credentials: credentials,
                                                       repository: repository)
                        watcher.enable()
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        watcher.batchRetry()
                        expect(try watcher.repository.countResources()).to(equal(1))
                    }
                }

                context("given limit reached") {
                    throwingIt("removes the report from database") {
                        urlSession.response = Mock403Response(url: URL(string: "https://yourteam.backtrace.io")!)
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       networkClient: networkClient,
                                                       credentials: credentials,
                                                       repository: repository)
                        watcher.enable()
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        watcher.batchRetry()
                        expect(try watcher.repository.countResources()).to(equal(1))
                    }
                }

                context("given new element") {
                    throwingIt("increments retry counter") {
                        urlSession.response = Mock403Response(url: URL(string: "https://yourteam.backtrace.io")!)
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       networkClient: networkClient,
                                                       credentials: credentials,
                                                       repository: repository)
                        watcher.enable()
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(report)

                        expect(watcher.repository.retryCount(for: report)).to(equal(0))
                        watcher.batchRetry()
                        expect(watcher.repository.retryCount(for: report)).to(equal(1))
                    }
                }
            }
        }
        // swiftlint:enable function_body_length
    }

    private static func backtraceReport(for attributes: Attributes) throws -> BacktraceReport {
        let crashReporter = BacktraceCrashReporter()
        return try crashReporter.generateLiveReport(attributes: attributes)
    }
}
