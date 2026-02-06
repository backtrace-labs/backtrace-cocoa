// swiftlint:disable force_try function_body_length

import Foundation
import Testing

@testable import Backtrace

extension BacktraceOomWatcher {
    /// BacktraceOomWatcher now performs all work asynchronously on its dedicated serial queue.
    /// The original unit-tests assume that the start(), handleLowMemoryWarning() and appChangedState(_:) invocations finish synchronously, so their assertions run before the queue has persisted state or updated the static attributes/attachments.
    /// **test-only**
    /// Blocks until all queued tasks have completed.
    func flushQueue() {
        queue.sync(flags: .barrier) { }
    }
}

@Suite(.serialized) struct BacktraceOomWatcherTests {

    // MARK: - Shared setup helper

    private static func makeOomWatcher(
        urlSession: URLSessionMock = URLSessionMock(),
        oomMode: BacktraceOomMode = .full,
        attributesProvider: AttributesProvider? = nil,
        newFile: URL = URL(fileURLWithPath: "newfile")
    ) throws -> (oomWatcher: BacktraceOomWatcher, urlSession: URLSessionMock, newFile: URL) {
        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let attrsProvider = attributesProvider ?? {
            let provider = AttributesProvider()
            try! "".write(to: newFile, atomically: true, encoding: .utf8)
            provider.attachments.append(newFile)
            return provider
        }()

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: attrsProvider,
                                              backtraceApi: backtraceApi,
                                              oomMode: oomMode)
        BacktraceOomWatcher.clean()
        urlSession.response = MockConnectionErrorResponse()

        return (oomWatcher, urlSession, newFile)
    }

    // MARK: - When enabled

    @Test("it saves the state with properties set")
    func savesStateWithPropertiesSet() throws {
        let (oomWatcher, _, _) = try BacktraceOomWatcherTests.makeOomWatcher()

        oomWatcher.start()
        oomWatcher.flushQueue()
        let savedState = oomWatcher._loadPreviousState()

        #expect(savedState?.state == BacktraceOomWatcher.ApplicationState.active)
        #expect(savedState?.appVersion == BacktraceOomWatcher.appVersion())
        #expect(savedState?.osVersion == ProcessInfo.processInfo.operatingSystemVersionString)
        #expect(savedState?.debugger == DebuggerChecker.isAttached())
        #expect(savedState?.memoryWarningReceived == false)
        #expect(BacktraceOomWatcher.reportAttributes == nil)
        #expect(BacktraceOomWatcher.reportAttachments == nil)
    }

    @Test("application state change results in updated state file")
    func applicationStateChangeUpdatesStateFile() throws {
        let (oomWatcher, _, _) = try BacktraceOomWatcherTests.makeOomWatcher()

        oomWatcher.start()
        oomWatcher.appChangedState(BacktraceOomWatcher.ApplicationState.background)
        oomWatcher.flushQueue()
        let savedState = oomWatcher._loadPreviousState()

        #expect(savedState?.state == BacktraceOomWatcher.ApplicationState.background)
    }

    @Test("low memory warning results in updated state file with resource and attributes")
    func lowMemoryWarningUpdatesStateFile() throws {
        let (oomWatcher, _, _) = try BacktraceOomWatcherTests.makeOomWatcher()

        oomWatcher.start()
        oomWatcher.handleLowMemoryWarning()
        oomWatcher.flushQueue()
        let savedState = oomWatcher._loadPreviousState()

        #expect(savedState?.memoryWarningReceived == true)
        #expect(BacktraceOomWatcher.reportAttributes != nil)
        #expect(BacktraceOomWatcher.reportAttachments?.first?.path.contains("newfile") == true)
    }

    @Test("calling handleLowMemory again within quiet times is noop")
    func handleLowMemoryQuietTimeIsNoop() throws {
        let (oomWatcher, _, _) = try BacktraceOomWatcherTests.makeOomWatcher()

        // Modify the quiet time so we can check if it re-saved the state after the quiet time expires
        oomWatcher.quietTimeInMillis = 500
        oomWatcher.attributesProvider.attachments.removeAll()

        oomWatcher.start()
        oomWatcher.handleLowMemoryWarning()
        oomWatcher.flushQueue()

        let shouldNotBeAddedFile = URL(fileURLWithPath: "should-not-be-added")
        try "".write(to: shouldNotBeAddedFile, atomically: true, encoding: .utf8)

        oomWatcher.attributesProvider.attachments.append(shouldNotBeAddedFile)
        oomWatcher.attributesProvider.attributes["should-not"] = "be-added"

        // All these should be NOOPs
        oomWatcher.handleLowMemoryWarning()
        oomWatcher.handleLowMemoryWarning()
        oomWatcher.handleLowMemoryWarning()
        oomWatcher.handleLowMemoryWarning()

        oomWatcher.flushQueue()

        #expect(BacktraceOomWatcher.reportAttachments?.isEmpty == true)
        #expect(BacktraceOomWatcher.reportAttributes?["should-not"] == nil)

        // after sleeping for the quietTime interval, it should add new attachments and attributes
        Thread.sleep(forTimeInterval: 0.5)

        oomWatcher.attributesProvider.attachments.removeAll()

        let shouldBeAddedFile = URL(fileURLWithPath: "should-be-added")
        try "".write(to: shouldBeAddedFile, atomically: true, encoding: .utf8)
        oomWatcher.attributesProvider.attachments.append(shouldBeAddedFile)
        oomWatcher.attributesProvider.attributes["should"] = "be-added"

        oomWatcher.handleLowMemoryWarning()
        oomWatcher.flushQueue()
        #expect(BacktraceOomWatcher.reportAttachments?.first?.path.contains("should-be-added") == true)
        #expect(BacktraceOomWatcher.reportAttributes?["should"] != nil)
    }

    // MARK: - When oomMode == .none

    @Test("does not create a state file or send reports when oomMode is none")
    func oomModeNoneDoesNotCreateStateFile() throws {
        let urlSession = URLSessionMock()
        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: AttributesProvider(),
                                              backtraceApi: backtraceApi,
                                              oomMode: .none)

        oomWatcher.start()
        oomWatcher.flushQueue()

        #expect(!FileManager.default.fileExists(atPath: BacktraceOomWatcher.oomFileURL!.path))
    }

    // MARK: - When oomMode == .light

    @Test("reports exactly once and off the main thread in light mode")
    func oomModeLightReportsOnce() throws {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        var willSendCalls = 0

        let newFile = URL(fileURLWithPath: "newfile")
        let attrsProvider = AttributesProvider()
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        attrsProvider.attachments.append(newFile)

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: attrsProvider,
                                              backtraceApi: backtraceApi,
                                              oomMode: .light)

        let delegate = BacktraceClientDelegateMock()
        delegate.willSendClosure = { report in
            willSendCalls += 1
            return report
        }
        backtraceApi.delegate = delegate

        oomWatcher.start()
        oomWatcher.state.debugger = false
        oomWatcher.handleLowMemoryWarning()
        oomWatcher.flushQueue()
        oomWatcher._sendPendingOomReports()
        oomWatcher.flushQueue()

        #expect(willSendCalls == 1)
    }

    // MARK: - With sending mocks: OOM report sent when requirements met

    @Test("results in oom report being sent when oom requirements met")
    func oomReportSentWhenRequirementsMet() throws {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let newFile = URL(fileURLWithPath: "newfile")
        let (oomWatcher, _, _) = try BacktraceOomWatcherTests.makeOomWatcher(urlSession: urlSession, newFile: newFile)
        urlSession.response = MockOkResponse()

        var calledWillSend = 0
        let delegate = BacktraceClientDelegateMock()

        delegate.willSendClosure = { report in
            calledWillSend += 1
            #expect(report.attachmentPaths.count == 1)
            #expect(report.attachmentPaths.first?.contains(newFile.path) == true)
            #expect(report.attributes["error.message"] as? String == "Out of memory detected.")
            #expect(report.attributes["error.type"] as? String == "Low Memory")
            #expect(report.attributes["state"] as? String == "active")
            #expect(report.attributes["guid"] as? String != nil)
            return report
        }

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

        let attrsProvider = AttributesProvider()
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        attrsProvider.attachments.append(newFile)

        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcherSend = BacktraceOomWatcher(repository: repository,
                                                  crashReporter: crashReporter,
                                                  attributes: attrsProvider,
                                                  backtraceApi: backtraceApi,
                                                  oomMode: .full)
        BacktraceOomWatcher.clean()
        urlSession.response = MockOkResponse()

        oomWatcherSend.start()

        // may be true when running in Xcode: override bc otherwise won't send the report
        oomWatcherSend.state.debugger = false

        oomWatcherSend.handleLowMemoryWarning()
        oomWatcherSend.flushQueue()

        backtraceApi.delegate = delegate
        oomWatcherSend._sendPendingOomReports()

        #expect(calledWillSend == 1)
    }

    @Test("can handle missing attributes and attachments")
    func canHandleMissingAttributesAndAttachments() throws {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let newFile = URL(fileURLWithPath: "newfile")

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

        let attrsProvider = AttributesProvider()
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        attrsProvider.attachments.append(newFile)

        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: attrsProvider,
                                              backtraceApi: backtraceApi,
                                              oomMode: .full)
        BacktraceOomWatcher.clean()
        urlSession.response = MockOkResponse()

        oomWatcher.start()

        // may be true when running in Xcode: override bc otherwise won't send the report
        oomWatcher.state.debugger = false

        oomWatcher.handleLowMemoryWarning()
        oomWatcher.flushQueue()

        BacktraceOomWatcher.reportAttributes = nil
        BacktraceOomWatcher.reportAttachments = nil

        var calledWillSend = 0
        let delegate = BacktraceClientDelegateMock()
        delegate.willSendClosure = { report in
            calledWillSend += 1

            #expect(report.attributes.isEmpty)
            #expect(report.attachmentPaths.isEmpty)

            return report
        }

        backtraceApi.delegate = delegate
        oomWatcher._sendPendingOomReports()

        #expect(calledWillSend == 1)
    }

    @Test("results in oom report NOT being sent when oom requirements NOT met: no warning")
    func oomReportNotSentNoWarning() throws {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let newFile = URL(fileURLWithPath: "newfile")

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

        let attrsProvider = AttributesProvider()
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        attrsProvider.attachments.append(newFile)

        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: attrsProvider,
                                              backtraceApi: backtraceApi,
                                              oomMode: .full)
        BacktraceOomWatcher.clean()
        urlSession.response = MockOkResponse()

        var calledWillSend = 0
        let delegate = BacktraceClientDelegateMock()
        delegate.willSendClosure = { report in
            calledWillSend += 1
            return report
        }

        // debugger attached: no report.
        oomWatcher.start()
        oomWatcher.state.debugger = true
        oomWatcher.state.memoryWarningReceived = false
        oomWatcher.handleLowMemoryWarning()

        backtraceApi.delegate = delegate
        oomWatcher._sendPendingOomReports()

        #expect(calledWillSend == 0)
    }

    @Test("results in oom report NOT being sent when oom requirements NOT met: no report")
    func oomReportNotSentNoReport() throws {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let newFile = URL(fileURLWithPath: "newfile")

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

        let attrsProvider = AttributesProvider()
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        attrsProvider.attachments.append(newFile)

        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: attrsProvider,
                                              backtraceApi: backtraceApi,
                                              oomMode: .full)
        BacktraceOomWatcher.clean()
        urlSession.response = MockOkResponse()

        var calledWillSend = 0
        let delegate = BacktraceClientDelegateMock()
        delegate.willSendClosure = { report in
            calledWillSend += 1
            return report
        }

        // no memory warning: no report.
        oomWatcher.start()
        oomWatcher.state.debugger = false

        backtraceApi.delegate = delegate
        oomWatcher._sendPendingOomReports()

        #expect(calledWillSend == 0)
    }

    @Test("results in oom report NOT being sent when oom requirements NOT met: other app version")
    func oomReportNotSentOtherAppVersion() throws {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let newFile = URL(fileURLWithPath: "newfile")

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

        let attrsProvider = AttributesProvider()
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        attrsProvider.attachments.append(newFile)

        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: attrsProvider,
                                              backtraceApi: backtraceApi,
                                              oomMode: .full)
        BacktraceOomWatcher.clean()
        urlSession.response = MockOkResponse()

        var calledWillSend = 0
        let delegate = BacktraceClientDelegateMock()
        delegate.willSendClosure = { report in
            calledWillSend += 1
            return report
        }

        // app version different: no report.
        oomWatcher.start()
        oomWatcher.state.debugger = false
        oomWatcher.state.appVersion = "1.2.3"
        oomWatcher.handleLowMemoryWarning()

        backtraceApi.delegate = delegate
        oomWatcher._sendPendingOomReports()

        #expect(calledWillSend == 0)
    }

    @Test("results in oom report NOT being sent when oom requirements NOT met: other OS version")
    func oomReportNotSentOtherOSVersion() throws {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let newFile = URL(fileURLWithPath: "newfile")

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

        let attrsProvider = AttributesProvider()
        try "".write(to: newFile, atomically: true, encoding: .utf8)
        attrsProvider.attachments.append(newFile)

        let crashReporter = BacktraceCrashReporter()
        let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

        let oomWatcher = BacktraceOomWatcher(repository: repository,
                                              crashReporter: crashReporter,
                                              attributes: attrsProvider,
                                              backtraceApi: backtraceApi,
                                              oomMode: .full)
        BacktraceOomWatcher.clean()
        urlSession.response = MockOkResponse()

        var calledWillSend = 0
        let delegate = BacktraceClientDelegateMock()
        delegate.willSendClosure = { report in
            calledWillSend += 1
            return report
        }

        // OS version different: no report.
        oomWatcher.start()
        oomWatcher.state.debugger = false
        oomWatcher.state.osVersion = "1.2.3"
        oomWatcher.handleLowMemoryWarning()

        backtraceApi.delegate = delegate
        oomWatcher._sendPendingOomReports()

        #expect(calledWillSend == 0)
    }
}
