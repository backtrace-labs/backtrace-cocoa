import Testing
import Foundation
@testable import Backtrace

@Suite struct BacktraceApiTests {

    private let crashReporter = BacktraceCrashReporter()
    private let urlSession = URLSessionMock()
    private let credentials =
        BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
    private let delegate = BacktraceClientDelegateSpy()

    private func makeApi(reportsPerMin: Int = 30) -> BacktraceApi {
        let api = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: reportsPerMin)
        delegate.clear()
        api.delegate = delegate
        return api
    }

    // MARK: - Valid HTTP response

    @Test("Given valid HTTP response, sends report and calls delegate methods")
    func validHTTPResponse() throws {
        let backtraceApi = makeApi()
        urlSession.response = MockOkResponse()
        let result = try backtraceApi.send(try crashReporter.generateLiveReport(attributes: [:]))
        #expect(result.backtraceStatus == BacktraceReportStatus.ok)

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledServerDidRespond)
        #expect(!delegate.calledConnectionDidFail)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
    }

    // MARK: - No HTTP response

    @Test("Given no HTTP response, sends report and calls delegate methods")
    func noHTTPResponse() throws {
        let backtraceApi = makeApi()
        urlSession.response = MockNoResponse()
        #expect(throws: (any Error).self) {
            try backtraceApi.send(try crashReporter.generateLiveReport(attributes: [:]))
        }

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledConnectionDidFail)
        #expect(!delegate.calledServerDidRespond)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
    }

    // MARK: - Connection error

    @Test("Given connection error, fails to send report and calls delegate methods")
    func connectionError() throws {
        let backtraceApi = makeApi()
        urlSession.response = MockConnectionErrorResponse()
        #expect(throws: (any Error).self) {
            try backtraceApi.send(try crashReporter.generateLiveReport(attributes: [:]))
        }

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledConnectionDidFail)
        #expect(!delegate.calledServerDidRespond)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
    }

    // MARK: - Forbidden HTTP response

    @Test("Given forbidden HTTP response, fails to send crash report and calls delegate methods")
    func forbiddenHTTPResponse() throws {
        let backtraceApi = makeApi()
        urlSession.response = Mock403Response()
        let report = try crashReporter.generateLiveReport(attributes: [:])
        let result = try backtraceApi.send(report)
        #expect(result.backtraceStatus == BacktraceReportStatus.serverError)

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledServerDidRespond)
        #expect(!delegate.calledConnectionDidFail)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
    }

    // MARK: - Too many reports (rate limit)

    @Test("Given too many reports to send, fails and calls limit reached delegate methods")
    func tooManyReportsRateLimit() throws {
        let backtraceApi = makeApi(reportsPerMin: 0)
        urlSession.response = MockOkResponse()
        let result = try backtraceApi.send(try crashReporter.generateLiveReport(attributes: [:]))
        #expect(result.backtraceStatus == .limitReached)

        #expect(!delegate.calledWillSend)
        #expect(!delegate.calledWillSendRequest)
        #expect(!delegate.calledServerDidRespond)
        #expect(!delegate.calledConnectionDidFail)
        #expect(delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 0)
    }

    // MARK: - New instance checks

    @Test("New instance has no delegate attached")
    func newInstanceNoDelegateAttached() {
        let api = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        #expect(api.delegate == nil)
    }

    @Test("New instance has empty timestamps list")
    func newInstanceEmptyTimestamps() {
        let api = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        #expect(api.backtraceRateLimiter.timestamps.isEmpty)
    }

    @Test("New instance can have delegate attached")
    func newInstanceDelegateAttachment() {
        let api = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        let mockDelegate = BacktraceClientDelegateMock()
        api.delegate = mockDelegate
        #expect(api.delegate != nil)
    }

    // MARK: - Report modification

    @Test("Can modify the report via delegate")
    func canModifyReport() throws {
        let backtraceApi = makeApi()
        let path1URL = URL(fileURLWithPath: "path1")
        let path2URL = URL(fileURLWithPath: "path2")

        let path1data = Data(count: 1024)
        let path2data = Data(count: 1024)

        try path1data.write(to: path1URL)
        try path2data.write(to: path2URL)

        let mockDelegate = BacktraceClientDelegateMock()
        let backtraceReport = try crashReporter.generateLiveReport(attributes: [:])
        let attachmentPaths = ["path1", "path2"]
        let header = (key: "foo", value: "bar")
        urlSession.response = MockOkResponse()
        backtraceApi.delegate = mockDelegate

        mockDelegate.willSendClosure = { report in
            report.attachmentPaths = attachmentPaths
            return report
        }

        mockDelegate.willSendRequestClosure = { request in
            var request = request
            request.addValue(header.key, forHTTPHeaderField: header.value)
            return request
        }

        let result = try backtraceApi.send(backtraceReport)

        #expect(result.backtraceStatus == .ok)
        #expect(result.report?.attachmentPaths == attachmentPaths)
    }
}
