import XCTest

import Nimble
import Quick
import CrashReporter
@testable import Backtrace

final class BacktraceClientTests: QuickSpec {

    // swiftlint:disable function_body_length
    override func spec() {

        describe("Backtrace client") {
            throwingContext("given default values") {
                guard let endpoint = URL(string: "https://wwww.backtrace.io") else { fail(); return }
                let token = "token"
                let credentials = BacktraceCredentials(endpoint: endpoint, token: token)

                it("has default database settings") {
                    let defaultDbSettings = BacktraceDatabaseSettings()
                    expect(defaultDbSettings.maxDatabaseSize).to(equal(0))
                    expect(defaultDbSettings.maxRecordCount).to(equal(0))
                    expect(defaultDbSettings.retryInterval).to(equal(5))
                    expect(defaultDbSettings.retryLimit).to(equal(3))
                    expect(defaultDbSettings.retryBehaviour.rawValue).to(equal(RetryBehaviour.interval.rawValue))
                    expect(defaultDbSettings.retryOrder.rawValue).to(equal(RetryOrder.queue.rawValue))
                    expect(defaultDbSettings.maxDatabaseSizeInBytes).to(equal(0))
                }

                it("has default configuration") {
                    let dbSettings = BacktraceDatabaseSettings()
                    let reportsPerMin = 3
                    let configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings,
                                                                     reportsPerMin: reportsPerMin,
                                                                     oomMode: .none)
                    expect(configuration.credentials).to(be(credentials))
                    expect(configuration.reportsPerMin).to(equal(reportsPerMin))
                    expect(configuration.dbSettings).to(be(dbSettings))
                    expect(configuration.loggingDestinations).to(beNil())
                    expect(configuration.delegate).to(beNil())
                }

                it("can create instance of BacktraceClient") {
                    expect { try BacktraceClient(credentials: credentials) }.notTo(throwError())
                }

                it("installs the configured delegate before startup repository replay") {
                    let session = URLSessionMock()
                    session.response = MockOkResponse()
                    let api = BacktraceApi(credentials: credentials, session: session, reportsPerMin: 30)
                    let dbSettings = BacktraceDatabaseSettings()
                    dbSettings.retryBehaviour = .interval
                    dbSettings.retryInterval = 3_600
                    let pendingReport = try BacktraceCrashReporter().generateLiveReport(attributes: [:])
                    let crashReporting = StartupCrashReportingMock(report: pendingReport)
                    let reporter = try BacktraceReporter(reporter: crashReporting,
                                                         api: api,
                                                         dbSettings: dbSettings,
                                                         credentials: credentials,
                                                         oomMode: .none,
                                                         networkAvailabilityCheck: { true })
                    try reporter.repository.clear()
                    try reporter.repository.save(pendingReport)
                    let startupDelegate = BacktraceClientDelegateSpy()
                    let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                                     dbSettings: dbSettings,
                                                                     oomMode: .none)
                    configuration.delegate = startupDelegate

                    let client = try BacktraceClient(configuration: configuration,
                                                     debugger: DetachedDebuggerCheckerMock.self,
                                                     reporter: reporter,
                                                     dispatcher: Dispatcher(),
                                                     api: api)

                    expect(startupDelegate.calledWillSend).toEventually(beTrue(), timeout: .seconds(2))
                    expect(startupDelegate.calledWillSendRequest).to(beTrue())
                    expect(startupDelegate.calledServerDidRespond).to(beTrue())
                    expect(session.requestCount).to(equal(1))
                    expect { try reporter.repository.countResources() }.toEventually(equal(0), timeout: .seconds(2))
                    expect(crashReporting.enableCalls).to(equal(1))
                    client.shutdownForNativeBridge()
                }

                it("preserves an injected API delegate when configuration delegate is nil") {
                    let api = BacktraceApi(credentials: credentials, reportsPerMin: 30)
                    let injectedDelegate = BacktraceClientDelegateSpy()
                    api.delegate = injectedDelegate
                    let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                         api: api,
                                                         dbSettings: BacktraceDatabaseSettings(),
                                                         credentials: credentials,
                                                         oomMode: .none)
                    let client = try BacktraceClient(configuration: BacktraceClientConfiguration(
                                                        credentials: credentials),
                                                     debugger: AttachedDebuggerCheckerMock.self,
                                                     reporter: reporter,
                                                     dispatcher: Dispatcher(),
                                                     api: api)

                    expect(api.delegate).to(beIdenticalTo(injectedDelegate))
                    client.shutdownForNativeBridge()
                }

                it("idempotently forwards native bridge shutdown to Cocoa background activity") {
                    let api = BacktraceApi(credentials: credentials, reportsPerMin: 30)
                    let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                         api: api,
                                                         dbSettings: BacktraceDatabaseSettings(),
                                                         credentials: credentials,
                                                         oomMode: .full)
                    let dispatcher = ShutdownDispatchingSpy()
                    let client = try BacktraceClient(configuration: BacktraceClientConfiguration(
                                                        credentials: credentials),
                                                     debugger: AttachedDebuggerCheckerMock.self,
                                                     reporter: reporter,
                                                     dispatcher: dispatcher,
                                                     api: api)
#if os(iOS) || os(OSX) || targetEnvironment(macCatalyst)
                    client.enableBreadcrumbs()
#endif

                    client.shutdownForNativeBridge()
                    client.shutdownForNativeBridge()

                    expect(client.isShutdown).to(beTrue())
                    expect(reporter.isShutdown).to(beTrue())
                    expect(api.isShutdown).to(beTrue())
                    expect(client.metrics.isShutdown).to(beTrue())
#if os(iOS) || os(OSX) || targetEnvironment(macCatalyst)
                    expect(client.breadcrumbs.isShutdown).to(beTrue())
                    expect(client.breadcrumbs.isBreadcrumbsEnabled).to(beFalse())
#endif
                    expect(dispatcher.shutdownCalls).to(equal(1))
                }

                it("waits for an in-progress concurrent native shutdown to finish") {
                    let api = BacktraceApi(credentials: credentials, reportsPerMin: 30)
                    let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                         api: api,
                                                         dbSettings: BacktraceDatabaseSettings(),
                                                         credentials: credentials,
                                                         oomMode: .none)
                    let dispatcher = BlockingShutdownDispatchingSpy()
                    let client = try BacktraceClient(configuration: BacktraceClientConfiguration(
                                                        credentials: credentials),
                                                     debugger: AttachedDebuggerCheckerMock.self,
                                                     reporter: reporter,
                                                     dispatcher: dispatcher,
                                                     api: api)
                    let firstReturned = DispatchSemaphore(value: 0)
                    let secondReturned = DispatchSemaphore(value: 0)

                    DispatchQueue.global().async {
                        client.shutdownForNativeBridge()
                        firstReturned.signal()
                    }
                    expect(dispatcher.entered.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    DispatchQueue.global().async {
                        client.shutdownForNativeBridge()
                        secondReturned.signal()
                    }

                    expect(secondReturned.wait(timeout: .now() + .milliseconds(100))).to(equal(.timedOut))
                    dispatcher.release.signal()
                    expect(firstReturned.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    expect(secondReturned.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    expect(client.isShutdown).to(beTrue())
                    expect(reporter.isShutdown).to(beTrue())
                }

                it("returns promptly, persists an in-flight cancellation, and completes exactly once") {
                    let session = HangingURLSession()
                    let api = BacktraceApi(credentials: credentials, session: session, reportsPerMin: 30)
                    let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                         api: api,
                                                         dbSettings: BacktraceDatabaseSettings(),
                                                         credentials: credentials,
                                                         oomMode: .none)
                    try reporter.repository.clear()
                    DynamicDebuggerCheckerMock.setAttached(true)
                    defer { DynamicDebuggerCheckerMock.setAttached(true) }
                    let client = try BacktraceClient(configuration: BacktraceClientConfiguration(
                                                        credentials: credentials),
                                                     debugger: DynamicDebuggerCheckerMock.self,
                                                     reporter: reporter,
                                                     dispatcher: Dispatcher(),
                                                     api: api)
                    DynamicDebuggerCheckerMock.setAttached(false)
                    let completionCalled = DispatchSemaphore(value: 0)
                    let completionLock = NSLock()
                    var completionResult: BacktraceResult?
                    client.send(message: "stalled report") { result in
                        completionLock.lock()
                        completionResult = result
                        completionLock.unlock()
                        completionCalled.signal()
                    }

                    expect(session.started.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    let shutdownReturned = DispatchSemaphore(value: 0)
                    DispatchQueue.global().async {
                        client.shutdownForNativeBridge()
                        shutdownReturned.signal()
                    }
                    expect(shutdownReturned.wait(timeout: .now() + .seconds(2))).to(equal(.success))

                    expect(session.cancelled.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    expect(completionCalled.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    expect(completionCalled.wait(timeout: .now() + .milliseconds(100))).to(equal(.timedOut))
                    completionLock.lock()
                    let result = completionResult
                    completionLock.unlock()
                    expect(result?.backtraceStatus).to(equal(.unknownError))
                    expect(try reporter.repository.countResources()).to(equal(1))
                }

                it("modifies the default values") {
                    let customDbSettings = BacktraceDatabaseSettings()
                    let maxRecordCount = 10
                    let maxDatabaseSize = 10
                    let retryInterval = 10
                    let retryBehaviour = RetryBehaviour.interval
                    let retryOrder = RetryOrder.stack
                    let retryLimit = 10

                    customDbSettings.maxRecordCount = maxRecordCount
                    customDbSettings.maxDatabaseSize = maxDatabaseSize
                    customDbSettings.retryInterval = retryInterval
                    customDbSettings.retryBehaviour = retryBehaviour
                    customDbSettings.retryOrder = retryOrder
                    customDbSettings.retryLimit = retryLimit

                    expect(customDbSettings.maxDatabaseSize).to(equal(maxDatabaseSize))
                    expect(customDbSettings.maxRecordCount).to(equal(maxRecordCount))
                    expect(customDbSettings.retryInterval).to(equal(retryInterval))
                    expect(customDbSettings.retryLimit).to(equal(retryLimit))
                    expect(customDbSettings.retryBehaviour.rawValue).to(equal(retryBehaviour.rawValue))
                    expect(customDbSettings.retryOrder.rawValue).to(equal(retryOrder.rawValue))
                    expect(customDbSettings.maxDatabaseSizeInBytes).to(equal(1024 * 1024 * maxDatabaseSize))
                }
            }
        }
    }
    // swiftlint:enable function_body_length
}

private enum DynamicDebuggerCheckerMock: DebuggerChecking {
    private static let lock = NSLock()
    private static var attached = true

    static func setAttached(_ value: Bool) {
        lock.lock()
        attached = value
        lock.unlock()
    }

    static func isAttached() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return attached
    }
}

private final class StartupCrashReportingMock: CrashReporting {
    private let report: BacktraceReport
    private(set) var enableCalls = 0

    init(report: BacktraceReport) {
        self.report = report
    }

    func generateLiveReport(exception: NSException?,
                            attributes: Attributes,
                            attachmentPaths: [String]) throws -> BacktraceReport {
        return report
    }

    func pendingCrashReport() throws -> BacktraceReport { return report }
    func purgePendingCrashReport() throws {}
    func hasPendingCrashes() -> Bool { return false }
    func enableCrashReporting() throws { enableCalls += 1 }
    func signalContext(_ mutableContext: inout SignalContext) {}
    func setCustomData(data: Data) {}
}

private final class ShutdownDispatchingSpy: Dispatching {
    private(set) var shutdownCalls = 0

    func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void) {
        block()
        completion()
    }

    func shutdown() {
        shutdownCalls += 1
    }
}

private final class BlockingShutdownDispatchingSpy: Dispatching {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func dispatch(_ block: @escaping () -> Void, completion: @escaping () -> Void) {
        block()
        completion()
    }

    func shutdown() {
        entered.signal()
        release.wait()
    }
}
