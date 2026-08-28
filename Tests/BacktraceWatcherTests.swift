import XCTest

import Nimble
import Quick
@testable import Backtrace

// Initial delivery, retry, and shutdown race cases intentionally exercise one shared watcher fixture.
// swiftlint:disable:next type_body_length
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
                urlSession.response = MockOkResponse()
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

                    throwingIt("makes one initial native-crash attempt and removes an accepted row") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        urlSession.response = MockOkResponse()
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                        repository.storeInitial(pending)

                        watcher.batchInitialSubmission()
                        watcher.batchRetry()

                        expect(urlSession.requestCount).to(equal(1))
                        expect(try repository.countResources()).to(equal(0))
                    }

                    throwingIt("makes one initial native-crash attempt but does not replay a transient failure") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        urlSession.response = MockHttpResponse(statusCode: 503)
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                        repository.storeInitial(pending)

                        watcher.batchInitialSubmission()
                        watcher.batchRetry()

                        expect(urlSession.requestCount).to(equal(1))
                        expect(try repository.countResources()).to(equal(1))
                        expect(repository.storage.first?.state).to(equal(.readyForRetry))
                    }

                    throwingIt("attempts once when reachability is false and transport is offline") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        urlSession.response = MockUrlErrorResponse(.notConnectedToInternet)
                        let initialQueue = DispatchQueue(label: "backtrace.watcher.none-offline-initial.tests")
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       dispatchQueue: initialQueue,
                                                       networkAvailabilityCheck: { false })
                        let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                        repository.storeInitial(pending)

                        watcher.submitInitialAsync()
                        initialQueue.sync {}
                        watcher.batchRetry()

                        expect(urlSession.requestCount).to(equal(1))
                        expect(try repository.countResources()).to(equal(1))
                        expect(repository.storage.first?.state).to(equal(.readyForRetry))
                        expect(repository.retryCount(for: pending)).to(equal(0))
                    }

                    throwingIt("leaves an unstarted initial row ready for the next process") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        let replayQueue = DispatchQueue(label: "backtrace.watcher.initial-shutdown.tests")
                        let queueEntered = DispatchSemaphore(value: 0)
                        let releaseQueue = DispatchSemaphore(value: 0)
                        replayQueue.async {
                            queueEntered.signal()
                            releaseQueue.wait()
                        }
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       dispatchQueue: replayQueue,
                                                       networkAvailabilityCheck: { true })
                        let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                        repository.storeInitial(pending)

                        expect(queueEntered.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                        watcher.submitInitialAsync()
                        watcher.shutdown()
                        watcher.submissionCoordinator.prepareForShutdown()
                        api.shutdown()
                        watcher.submissionCoordinator.finishShutdown(whenQuiesced: {})
                        releaseQueue.signal()
                        replayQueue.sync {}

                        expect(urlSession.requestCount).to(equal(0))
                        expect(repository.storage.first?.state).to(equal(.readyForInitialSubmission))
                    }

                    throwingIt("reschedules a queued pending crash after a live report fills the rate window") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        urlSession.response = MockOkResponse()
                        var now = 1_000.0
                        let limitedApi = BacktraceApi(credentials: credentials,
                                                      session: urlSession,
                                                      reportsPerMin: 1,
                                                      rateLimiterCurrentTime: { now })
                        let initialQueue = DispatchQueue(label: "backtrace.watcher.initial-admission.tests")
                        let queueEntered = DispatchSemaphore(value: 0)
                        let releaseQueue = DispatchSemaphore(value: 0)
                        initialQueue.async {
                            queueEntered.signal()
                            releaseQueue.wait()
                        }
                        let scheduler = InitialAdmissionSchedulerSpy()
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: limitedApi,
                                                       repository: repository,
                                                       dispatchQueue: initialQueue,
                                                       networkAvailabilityCheck: { true },
                                                       initialAdmissionScheduler: scheduler.schedule)
                        let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                        repository.storeInitial(pending)
                        let delegate = BacktraceClientDelegateMock()
                        let rateLimitCallback = DispatchSemaphore(value: 0)
                        delegate.didReachLimitClosure = { _ in
                            expect(repository.storage.first?.state)
                                .to(equal(.readyForInitialSubmission))
                            expect(repository.retryCount(for: pending)).to(equal(0))
                            rateLimitCallback.signal()
                        }
                        limitedApi.delegate = delegate

                        expect(queueEntered.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                        watcher.submitInitialAsync()
                        _ = try limitedApi.send(
                            BacktraceWatcherTests.backtraceReport(for: ["live": true])
                        )
                        releaseQueue.signal()
                        initialQueue.sync {}

                        expect(rateLimitCallback.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                        expect(urlSession.requestCount).to(equal(1))
                        expect(repository.storage.first?.state).to(equal(.readyForInitialSubmission))
                        expect(repository.retryCount(for: pending)).to(equal(0))
                        expect(scheduler.count).to(equal(1))
                        expect(scheduler.nextDelay).to(equal(60))

                        // Repeated triggers share the same pending admission check.
                        watcher.drainInitialSubmissions(bypassesReachabilityPreflight: true)
                        expect(scheduler.count).to(equal(1))

                        now = 1_060
                        scheduler.runNext()

                        expect(urlSession.requestCount).to(equal(2))
                        expect(try repository.countResources()).to(equal(0))
                        expect(scheduler.count).to(equal(0))
                    }

                    throwingIt("drains more than one bounded page of initial reports") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        let unlimitedApi = BacktraceApi(credentials: credentials,
                                                        session: urlSession,
                                                        reportsPerMin: 0)
                        let initialQueue = DispatchQueue(
                            label: "backtrace.watcher.initial-page-drain.tests"
                        )
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: unlimitedApi,
                                                       repository: repository,
                                                       dispatchQueue: initialQueue,
                                                       networkAvailabilityCheck: { true })
                        for index in 0..<15 {
                            repository.storeInitial(try BacktraceWatcherTests.backtraceReport(
                                for: ["initialIndex": index]
                            ))
                        }

                        watcher.submitInitialAsync()
                        initialQueue.sync {}

                        expect(urlSession.requestCount).to(equal(15))
                        expect(try repository.countResources()).to(equal(0))
                    }

                    for lostIndex in [0, 1] {
                        throwingIt("continues the current initial page after claim contention at index \(lostIndex)") {
                            dbSettings.retryBehaviour = .none
                            try repository.clear()
                            let watcher = BacktraceWatcher(settings: dbSettings,
                                                           api: api,
                                                           repository: repository,
                                                           networkAvailabilityCheck: { true })
                            let reports = try (0..<3).map { index in
                                try BacktraceWatcherTests.backtraceReport(for: ["claimIndex": index])
                            }
                            reports.forEach(repository.storeInitial)
                            let lostIdentifier = reports[lostIndex].identifier
                            repository.initialClaimDecision = { $0.identifier != lostIdentifier }

                            watcher.drainInitialSubmissions(bypassesReachabilityPreflight: true)

                            expect(urlSession.requestCount).to(equal(2))
                            expect(repository.storage.map(\.resource.identifier))
                                .to(equal([lostIdentifier]))
                            expect(repository.storage.first?.state)
                                .to(equal(.initialSubmissionInFlight))
                            expect(repository.storage.first?.deliveryOwner)
                                .to(equal("competing-initial-owner"))
                        }
                    }

                    throwingIt("does not spin when every initial claim is owned elsewhere") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        for index in 0..<3 {
                            repository.storeInitial(try BacktraceWatcherTests.backtraceReport(
                                for: ["contendedIndex": index]
                            ))
                        }
                        var claimCount = 0
                        repository.initialClaimDecision = { _ in
                            claimCount += 1
                            return false
                        }

                        watcher.drainInitialSubmissions(bypassesReachabilityPreflight: true)

                        expect(claimCount).to(equal(3))
                        expect(urlSession.requestCount).to(equal(0))
                        expect(try repository.countResources()).to(equal(3))
                        expect(repository.storage.allSatisfy {
                            $0.state == .initialSubmissionInFlight
                        }).to(beTrue())
                    }

                    throwingIt("continues to a later page after the first page is claimed elsewhere") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let reports = try (0..<11).map { index in
                            try BacktraceWatcherTests.backtraceReport(for: ["pagedContention": index])
                        }
                        reports.forEach(repository.storeInitial)
                        let contendedIdentifiers = Set(reports.prefix(10).map(\.identifier))
                        repository.initialClaimDecision = {
                            !contendedIdentifiers.contains($0.identifier)
                        }

                        watcher.drainInitialSubmissions(bypassesReachabilityPreflight: true)

                        expect(urlSession.requestCount).to(equal(1))
                        expect(repository.storage.map(\.resource.identifier))
                            .to(equal(Array(reports.prefix(10).map(\.identifier))))
                        expect(repository.storage.allSatisfy {
                            $0.state == .initialSubmissionInFlight
                        }).to(beTrue())
                    }

                    throwingIt("submits a previously contended row after the competing owner exits") {
                        dbSettings.retryBehaviour = .none
                        try repository.clear()
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let contended = try BacktraceWatcherTests.pendingBacktraceReport()
                        let available = try BacktraceWatcherTests.backtraceReport(for: ["available": true])
                        repository.storeInitial(contended)
                        repository.storeInitial(available)
                        var competingOwnerIsActive = true
                        repository.initialClaimDecision = { report in
                            report.identifier != contended.identifier || !competingOwnerIsActive
                        }

                        watcher.drainInitialSubmissions(bypassesReachabilityPreflight: true)
                        expect(urlSession.requestCount).to(equal(1))
                        expect(repository.storage.map(\.resource.identifier))
                            .to(equal([contended.identifier]))
                        expect(repository.storage.first?.state)
                            .to(equal(.initialSubmissionInFlight))

                        competingOwnerIsActive = false
                        repository.competingInitialOwnerIsAlive = false
                        watcher.drainInitialSubmissions(bypassesReachabilityPreflight: true)

                        expect(urlSession.requestCount).to(equal(2))
                        expect(try repository.countResources()).to(equal(0))
                    }
                }
            }

            context("given enabled retry behaviour") {
                throwingIt("fires timer") {
                    dbSettings.retryBehaviour = .interval
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: api,
                                                   repository: repository)
                    defer { watcher.shutdown() }
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
                        watcher.submissionCoordinator.prepareForShutdown()
                        hangingApi.shutdown()
                        watcher.finishShutdown()
                        watcher.submissionCoordinator.finishShutdown(whenQuiesced: {})
                        shutdownReturned.signal()
                    }
                    expect(shutdownReturned.wait(timeout: .now() + .seconds(2))).to(equal(.success))

                    expect(session.cancelled.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    replayQueue.sync {}
                    expect(try repository.countResources()).to(equal(1))
                    expect(repository.retryCount(for: report)).to(equal(0))
                }

                throwingIt("does not retry a transient initial failure in the same timer cycle") {
                    try repository.clear()
                    urlSession.response = MockHttpResponse(statusCode: 503)
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: api,
                                                   repository: repository,
                                                   networkAvailabilityCheck: { true })
                    let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                    repository.storeInitial(pending)

                    watcher.timerEventHandler()

                    expect(urlSession.requestCount).to(equal(1))
                    expect(repository.storage.first?.state).to(equal(.readyForRetry))

                    urlSession.response = MockOkResponse()
                    watcher.timerEventHandler()

                    expect(urlSession.requestCount).to(equal(2))
                    expect(try repository.countResources()).to(equal(0))
                }

                throwingIt("picks up an initial row on a later interval after startup was offline") {
                    try repository.clear()
                    var networkAvailable = false
                    let watcherQueue = DispatchQueue(label: "backtrace.watcher.offline-initial.tests")
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: api,
                                                   repository: repository,
                                                   dispatchQueue: watcherQueue,
                                                   networkAvailabilityCheck: { networkAvailable })
                    let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                    repository.storeInitial(pending)

                    watcher.submitInitialAsync()
                    watcherQueue.sync {}

                    expect(urlSession.requestCount).to(equal(0))
                    expect(repository.storage.first?.state).to(equal(.readyForInitialSubmission))

                    networkAvailable = true
                    watcher.timerEventHandler()

                    expect(urlSession.requestCount).to(equal(1))
                    expect(try repository.countResources()).to(equal(0))
                }

                throwingIt("keeps a locally limited initial row out of ordinary replay") {
                    try repository.clear()
                    var now = 2_000.0
                    let limitedApi = BacktraceApi(credentials: credentials,
                                                  session: urlSession,
                                                  reportsPerMin: 1,
                                                  rateLimiterCurrentTime: { now })
                    _ = try limitedApi.send(
                        BacktraceWatcherTests.backtraceReport(for: ["fillsWindow": true])
                    )
                    let scheduler = InitialAdmissionSchedulerSpy()
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: limitedApi,
                                                   repository: repository,
                                                   networkAvailabilityCheck: { true },
                                                   initialAdmissionScheduler: scheduler.schedule)
                    let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                    repository.storeInitial(pending)

                    watcher.drainInitialSubmissions()
                    watcher.batchRetry()

                    expect(urlSession.requestCount).to(equal(1))
                    expect(repository.storage.first?.state).to(equal(.readyForInitialSubmission))
                    expect(repository.retryCount(for: pending)).to(equal(0))
                    expect(scheduler.count).to(equal(1))

                    now = 2_060
                    scheduler.runNext()

                    expect(urlSession.requestCount).to(equal(2))
                    expect(try repository.countResources()).to(equal(0))
                }

                throwingIt("cancels a scheduled initial admission check during shutdown") {
                    try repository.clear()
                    let limitedApi = BacktraceApi(credentials: credentials,
                                                  session: urlSession,
                                                  reportsPerMin: 1)
                    _ = try limitedApi.send(
                        BacktraceWatcherTests.backtraceReport(for: ["fillsWindow": true])
                    )
                    let scheduler = InitialAdmissionSchedulerSpy()
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   api: limitedApi,
                                                   repository: repository,
                                                   networkAvailabilityCheck: { true },
                                                   initialAdmissionScheduler: scheduler.schedule)
                    repository.storeInitial(try BacktraceWatcherTests.pendingBacktraceReport())

                    watcher.drainInitialSubmissions()
                    expect(scheduler.count).to(equal(1))

                    watcher.shutdown()

                    expect(scheduler.nextIsCancelled).to(beTrue())
                    scheduler.runNext()
                    expect(urlSession.requestCount).to(equal(1))
                    expect(repository.storage.first?.state).to(equal(.readyForInitialSubmission))
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

                    throwingIt("retries a failed initial native-crash attempt when interval replay is enabled") {
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       api: api,
                                                       repository: repository,
                                                       networkAvailabilityCheck: { true })
                        let pending = try BacktraceWatcherTests.pendingBacktraceReport()
                        repository.storeInitial(pending)
                        urlSession.response = MockHttpResponse(statusCode: 503)

                        watcher.batchInitialSubmission()
                        expect(urlSession.requestCount).to(equal(1))
                        expect(repository.storage.first?.state).to(equal(.readyForRetry))

                        urlSession.response = MockOkResponse()
                        watcher.batchRetry()

                        expect(urlSession.requestCount).to(equal(2))
                        expect(try repository.countResources()).to(equal(0))
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

            describe("Submission finalization races") {
                for statusCode in [200, 403] {
                    throwingIt("finalizes HTTP \(statusCode) before shutdown quiesces the repository") {
                        let raceRepository = WatcherRepositoryMock<BacktraceReport>()
                        let raceSession = URLSessionMock()
                        raceSession.response = MockHttpResponse(statusCode: statusCode)
                        let raceApi = BacktraceApi(credentials: credentials,
                                                   session: raceSession,
                                                   reportsPerMin: 30)
                        let barrier = SubmissionFinalizationBarrier()
                        let coordinator = BacktraceSubmissionCoordinator(
                            api: raceApi,
                            repository: raceRepository,
                            retryLimit: dbSettings.retryLimit,
                            beforeFinalization: barrier.pause)
                        let watcher = BacktraceWatcher(settings: dbSettings,
                                                       submissionCoordinator: coordinator,
                                                       repository: raceRepository,
                                                       networkAvailabilityCheck: { true })
                        let report = try BacktraceWatcherTests.backtraceReport(for: ["status": statusCode])
                        try raceRepository.save(report)
                        let sendFinished = DispatchSemaphore(value: 0)
                        DispatchQueue.global().async {
                            watcher.batchRetry()
                            sendFinished.signal()
                        }

                        expect(barrier.reached.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                        watcher.prepareForShutdown()
                        coordinator.prepareForShutdown()
                        raceApi.shutdown()
                        watcher.finishShutdown()
                        let quiesced = DispatchSemaphore(value: 0)
                        coordinator.finishShutdown { quiesced.signal() }
                        barrier.release.signal()

                        expect(sendFinished.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                        expect(quiesced.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                        expect(raceSession.requestCount).to(equal(1))
                        expect(try raceRepository.countResources()).to(equal(0))
                    }
                }

                throwingIt("durably retains HTTP 503 when shutdown races finalization") {
                    let raceRepository = WatcherRepositoryMock<BacktraceReport>()
                    let raceSession = URLSessionMock()
                    raceSession.response = MockHttpResponse(statusCode: 503)
                    let raceApi = BacktraceApi(credentials: credentials,
                                               session: raceSession,
                                               reportsPerMin: 30)
                    let barrier = SubmissionFinalizationBarrier()
                    let coordinator = BacktraceSubmissionCoordinator(
                        api: raceApi,
                        repository: raceRepository,
                        retryLimit: dbSettings.retryLimit,
                        beforeFinalization: barrier.pause)
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   submissionCoordinator: coordinator,
                                                   repository: raceRepository,
                                                   networkAvailabilityCheck: { true })
                    let report = try BacktraceWatcherTests.backtraceReport(for: ["status": 503])
                    try raceRepository.save(report)
                    let sendFinished = DispatchSemaphore(value: 0)
                    DispatchQueue.global().async {
                        watcher.batchRetry()
                        sendFinished.signal()
                    }

                    expect(barrier.reached.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    watcher.prepareForShutdown()
                    coordinator.prepareForShutdown()
                    raceApi.shutdown()
                    watcher.finishShutdown()
                    coordinator.finishShutdown(whenQuiesced: {})
                    barrier.release.signal()
                    expect(sendFinished.wait(timeout: .now() + .seconds(2))).to(equal(.success))

                    expect(raceSession.requestCount).to(equal(1))
                    expect(try raceRepository.countResources()).to(equal(1))
                    expect(raceRepository.storage.first?.state).to(equal(.readyForRetry))
                    expect(raceRepository.retryCount(for: report)).to(equal(1))
                }

                throwingIt("commits a rate-limited row before shutdown and its delegate callback") {
                    let raceRepository = WatcherRepositoryMock<BacktraceReport>()
                    let raceSession = URLSessionMock()
                    raceSession.response = MockOkResponse()
                    let limitedApi = BacktraceApi(credentials: credentials,
                                                  session: raceSession,
                                                  reportsPerMin: 1)
                    _ = try limitedApi.send(BacktraceWatcherTests.backtraceReport(for: ["fills": true]))
                    let delegate = BacktraceClientDelegateMock()
                    let callback = DispatchSemaphore(value: 0)
                    delegate.didReachLimitClosure = { _ in
                        expect(raceRepository.storage.first?.state).to(equal(.readyForRetry))
                        expect(raceRepository.retryCount(for: raceRepository.storage[0].resource)).to(equal(0))
                        callback.signal()
                    }
                    limitedApi.delegate = delegate
                    let barrier = SubmissionFinalizationBarrier()
                    let coordinator = BacktraceSubmissionCoordinator(
                        api: limitedApi,
                        repository: raceRepository,
                        retryLimit: dbSettings.retryLimit,
                        beforeFinalization: barrier.pause)
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   submissionCoordinator: coordinator,
                                                   repository: raceRepository,
                                                   networkAvailabilityCheck: { true })
                    let report = try BacktraceWatcherTests.backtraceReport(for: ["limited": true])
                    try raceRepository.save(report)
                    let sendFinished = DispatchSemaphore(value: 0)
                    DispatchQueue.global().async {
                        watcher.batchRetry()
                        sendFinished.signal()
                    }

                    expect(barrier.reached.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    watcher.prepareForShutdown()
                    coordinator.prepareForShutdown()
                    limitedApi.shutdown()
                    watcher.finishShutdown()
                    coordinator.finishShutdown(whenQuiesced: {})
                    barrier.release.signal()
                    expect(sendFinished.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    expect(callback.wait(timeout: .now() + .seconds(2))).to(equal(.success))

                    expect(raceSession.requestCount).to(equal(1))
                    expect(raceRepository.storage.first?.state).to(equal(.readyForRetry))
                    expect(raceRepository.retryCount(for: report)).to(equal(0))
                }

                throwingIt("invokes a reentrant server delegate only after terminal deletion") {
                    let raceRepository = WatcherRepositoryMock<BacktraceReport>()
                    let raceSession = URLSessionMock()
                    raceSession.response = MockOkResponse()
                    let raceApi = BacktraceApi(credentials: credentials,
                                               session: raceSession,
                                               reportsPerMin: 30)
                    let coordinator = BacktraceSubmissionCoordinator(api: raceApi,
                                                                     repository: raceRepository,
                                                                     retryLimit: dbSettings.retryLimit)
                    let watcher = BacktraceWatcher(settings: dbSettings,
                                                   submissionCoordinator: coordinator,
                                                   repository: raceRepository,
                                                   networkAvailabilityCheck: { true })
                    let delegate = BacktraceClientDelegateMock()
                    let callback = DispatchSemaphore(value: 0)
                    delegate.serverDidRespondClosure = { _ in
                        expect(try? raceRepository.countResources()).to(equal(0))
                        watcher.prepareForShutdown()
                        coordinator.prepareForShutdown()
                        raceApi.shutdown()
                        watcher.finishShutdown()
                        coordinator.finishShutdown(whenQuiesced: {})
                        callback.signal()
                    }
                    raceApi.delegate = delegate
                    try raceRepository.save(BacktraceWatcherTests.backtraceReport(for: ["reentrant": true]))

                    watcher.batchRetry()

                    expect(callback.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    expect(raceSession.requestCount).to(equal(1))
                    expect(try raceRepository.countResources()).to(equal(0))
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

private final class SubmissionFinalizationBarrier {
    let reached = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func pause(_ outcome: BacktraceSubmissionOutcome) {
        _ = outcome
        reached.signal()
        release.wait()
    }
}

private final class InitialAdmissionSchedulerSpy {
    private var scheduled = [(delay: TimeInterval, workItem: DispatchWorkItem)]()

    var count: Int { scheduled.count }
    var nextDelay: TimeInterval? { scheduled.first?.delay }
    var nextIsCancelled: Bool { scheduled.first?.workItem.isCancelled ?? false }

    func schedule(delay: TimeInterval, workItem: DispatchWorkItem) {
        scheduled.append((delay, workItem))
    }

    func runNext() {
        guard !scheduled.isEmpty else { return }
        let workItem = scheduled.removeFirst().workItem
        workItem.perform()
    }
}
