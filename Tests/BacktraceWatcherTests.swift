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
            var api = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

            beforeEach {
                dbSettings.retryBehaviour = .interval
                dbSettings.retryOrder = .queue
                api = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                urlSession.resetRequestCount()
            }

            context("given default values") {

                throwingIt("sets the timer") {
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: api,
                                                   repository: repository)
                    expect(watcher.settings).to(be(dbSettings))
                    expect(watcher.api).to(be(api))
                    expect(watcher.repository).to(be(repository))
                    expect(watcher.timer).to(beNil())
                }

                context("given disabled retry behaviour") {
                    throwingIt("does not configure a timer") {
                        dbSettings.retryBehaviour = .none
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        expect(watcher.timer).to(beNil())
                    }

                    throwingIt("performs no startup replay traffic") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        let replayQueue = DispatchQueue(label: "backtrace.watcher.startup-replay.tests")
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       dispatchQueue: replayQueue,
                                                       networkAvailabilityCheck: { true })
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        watcher.replayAsync()
                        watcher.batchRetry()
                        replayQueue.sync {}

                        expect(try watcher.repository.countResources()).to(equal(1))
                        expect(urlSession.requestCount).to(equal(0))
                    }
                }
            }

            context("given enabled retry behaviour") {
                throwingIt("fires timer") {
                    dbSettings.retryBehaviour = .interval
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: api,
                                                   repository: repository)
                    watcher.resetTimer()
                    watcher.enable()
                    // spec will be updated after upgrading Quick & Nimble to resolve Fastlane hangs
                    expect(watcher.timer).toNot(beNil())
                }

                throwingIt("shuts down timers and queued replay idempotently") {
                    try repository.clear()
                    let replayQueue = DispatchQueue(label: "backtrace.watcher.shutdown.tests")
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: api,
                                                   repository: repository,
                                                   dispatchQueue: replayQueue,
                                                   networkAvailabilityCheck: { true })
                    try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                    watcher.enable()
                    expect(watcher.timer).toNot(beNil())

                    watcher.shutdown()
                    watcher.shutdown()
                    watcher.replayAsync()
                    watcher.batchRetry()
                    watcher.enable()
                    replayQueue.sync {}

                    expect(watcher.isShutdown).to(beTrue())
                    expect(watcher.timer).to(beNil())
                    expect(try repository.countResources()).to(equal(1))
                    expect(urlSession.requestCount).to(equal(0))
                }

                throwingIt("cancels an in-flight replay without blocking or mutating its repository row") {
                    try repository.clear()
                    let session = HangingURLSession()
                    let hangingApi = BacktraceApi(credentials: credentials,
                                                  session: session,
                                                  reportsPerMin: 30)
                    let replayQueue = DispatchQueue(label: "backtrace.watcher.hanging.tests")
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: hangingApi,
                                                   repository: repository,
                                                   dispatchQueue: replayQueue,
                                                   networkAvailabilityCheck: { true })
                    let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                    try repository.save(report)
                    replayQueue.async { watcher.batchRetry() }

                    expect(session.started.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    let shutdownReturned = DispatchSemaphore(value: 0)
                    DispatchQueue.global().async {
                        watcher.prepareForShutdown()
                        hangingApi.shutdown()
                        watcher.finishShutdown()
                        shutdownReturned.signal()
                    }
                    expect(shutdownReturned.wait(timeout: .now() + .seconds(2))).to(equal(.success))

                    expect(session.cancelled.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    replayQueue.sync {}
                    expect(try repository.countResources()).to(equal(1))
                    expect(repository.retryCount(for: report)).to(equal(0))
                }
            }

            describe("Accessing resources") {
                throwingBeforeEach { try repository.clear() }

                context("given one element") {
                    throwingIt("completes successfully") {
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        watcher.enable()
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        expect { try watcher.reportsFromRepository(limit: 1) }.toNot(throwError())
                    }
                }

                context("given queue order") {
                    throwingIt("gets the oldest element") {
                        dbSettings.retryOrder = .queue
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
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
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
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
                    throwingIt("uses the shared delegate-aware API for a pending native report") {
                        let delegate = BacktraceClientDelegateSpy()
                        api.delegate = delegate
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        try repository.save(BacktraceWatcherTests.pendingBacktraceReport())

                        watcher.batchRetry()

                        expect(try watcher.repository.countResources()).to(equal(0))
                        expect(delegate.calledWillSend).to(beTrue())
                        expect(delegate.calledWillSendRequest).to(beTrue())
                        expect(delegate.calledServerDidRespond).to(beTrue())
                        expect(delegate.calledConnectionDidFail).to(beFalse())
                        expect(delegate.calledDidReachLimit).to(beFalse())
                    }
                }

                context("given two elements") {
                    throwingIt("removes them from repository") {
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 2]))
                        watcher.batchRetry()

                        expect(try watcher.repository.countResources()).to(equal(0))
                    }
                }

                context("given connection error") {
                    throwingIt("retains the report, records the retry, and emits the failure callback") {
                        urlSession.response =
                            MockConnectionErrorResponse(url: URL(string: "https://yourteam.backtrace.io")!)
                        let delegate = BacktraceClientDelegateSpy()
                        api.delegate = delegate
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(report)

                        watcher.batchRetry()
                        expect(try watcher.repository.countResources()).to(equal(1))
                        expect(watcher.repository.retryCount(for: report)).to(equal(1))
                        expect(delegate.calledWillSend).to(beTrue())
                        expect(delegate.calledWillSendRequest).to(beTrue())
                        expect(delegate.calledConnectionDidFail).to(beTrue())
                        expect(delegate.calledServerDidRespond).to(beFalse())
                    }
                }

                context("given a permanent URL configuration error") {
                    throwingIt("removes the report without consuming a retry and emits the failure callback") {
                        urlSession.response = MockUrlErrorResponse(.unsupportedURL)
                        let delegate = BacktraceClientDelegateSpy()
                        api.delegate = delegate
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(report)

                        watcher.batchRetry()

                        expect(try repository.countResources()).to(equal(0))
                        expect(repository.retryCount(for: report)).to(equal(0))
                        expect(delegate.calledWillSend).to(beTrue())
                        expect(delegate.calledWillSendRequest).to(beTrue())
                        expect(delegate.calledConnectionDidFail).to(beTrue())
                        expect(delegate.calledServerDidRespond).to(beFalse())
                    }
                }

                context("given a permanent HTTP rejection") {
                    throwingIt("removes the report without retrying it") {
                        urlSession.response = Mock403Response(url: URL(string: "https://yourteam.backtrace.io")!)
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        try repository.save(BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1]))

                        watcher.batchRetry()
                        expect(try watcher.repository.countResources()).to(equal(0))
                    }

                    throwingIt("does not resubmit or increment when terminal cleanup is deferred") {
                        urlSession.response = Mock403Response()
                        repository.deleteError = FileError.fileNotWritten
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(report)

                        watcher.batchRetry()
                        watcher.batchRetry()

                        expect(urlSession.requestCount).to(equal(1))
                        expect(try repository.countResources()).to(equal(1))
                        expect(repository.retryCount(for: report)).to(equal(0))
                        expect(repository.terminalIdentifiers).to(contain(report.identifier))
                    }
                }

                context("given an accepted response whose cleanup is deferred") {
                    throwingIt("does not submit the accepted report twice") {
                        urlSession.response = MockOkResponse()
                        repository.deleteError = FileError.fileNotWritten
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(report)

                        watcher.batchRetry()
                        watcher.batchRetry()

                        expect(urlSession.requestCount).to(equal(1))
                        expect(try repository.countResources()).to(equal(1))
                        expect(repository.retryCount(for: report)).to(equal(0))
                        expect(repository.terminalIdentifiers).to(contain(report.identifier))
                    }
                }

                context("given a retryable HTTP rejection") {
                    throwingIt("retains the report and increments its retry counter") {
                        urlSession.response = MockHttpResponse(statusCode: 503)
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["testOrder": 1])
                        try repository.save(report)

                        expect(watcher.repository.retryCount(for: report)).to(equal(0))
                        watcher.batchRetry()
                        expect(watcher.repository.retryCount(for: report)).to(equal(1))
                    }
                }

                context("given a full shared rate window") {
                    throwingIt("does not bypass the limiter or consume a repository retry") {
                        let delegate = BacktraceClientDelegateSpy()
                        let limitedApi = BacktraceApi(credentials: credentials,
                                                      session: urlSession,
                                                      reportsPerMin: 1)
                        limitedApi.delegate = delegate
                        _ = try limitedApi.send(BacktraceWatcherTests.backtraceReport(for: ["initial": true]))
                        delegate.clear()

                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: limitedApi,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let persisted = try BacktraceWatcherTests.backtraceReport(for: ["persisted": true])
                        try repository.save(persisted)

                        watcher.batchRetry()

                        expect(urlSession.requestCount).to(equal(1))
                        expect(try repository.countResources()).to(equal(1))
                        expect(repository.retryCount(for: persisted)).to(equal(0))
                        expect(delegate.calledDidReachLimit).to(beTrue())
                        expect(delegate.calledWillSend).to(beFalse())
                        expect(delegate.calledWillSendRequest).to(beFalse())
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

    private static func pendingBacktraceReport() throws -> BacktraceReport {
        let liveReport = try backtraceReport(for: [:])
        return try BacktraceReport(pendingReport: liveReport.reportData,
                                   attributes: ["pending": true],
                                   attachmentPaths: [])
    }
}
