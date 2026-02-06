// swiftlint:disable function_body_length force_try

import Foundation
import Testing

@testable import Backtrace

@Suite(.serialized) struct BacktraceReporterTests {

    // MARK: - Shared setup helper

    private static func makeReporter(
        urlSession: URLSessionMock = URLSessionMock()
    ) throws -> (reporter: BacktraceReporter, urlSession: URLSessionMock, backtraceApi: BacktraceApi, delegate: BacktraceClientDelegateSpy) {
        // Clear global breadcrumb state to avoid cross-test contamination
        BreadcrumbsInfo.breadcrumbFile = nil
        BreadcrumbsInfo.currentBreadcrumbsId = nil

        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let delegate = BacktraceClientDelegateSpy()
        delegate.clear()
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                              api: backtraceApi,
                                              dbSettings: BacktraceDatabaseSettings(),
                                              credentials: credentials,
                                              oomMode: .full,
                                              urlSession: urlSession)
        try reporter.repository.clear()
        reporter.delegate = delegate
        return (reporter, urlSession, backtraceApi, delegate)
    }

    // MARK: - Given valid HTTP response

    @Test("sends report and calls delegate methods with valid HTTP response")
    func validHTTPResponse() throws {
        let (reporter, urlSession, backtraceApi, delegate) = try BacktraceReporterTests.makeReporter()
        urlSession.response = MockOkResponse()

        let result = reporter.send(resource: try reporter.generate())
        #expect(result.backtraceStatus == .ok)

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledServerDidRespond)
        #expect(!delegate.calledConnectionDidFail)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
        #expect(try reporter.repository.countResources() == 0)
    }

    // MARK: - Given no HTTP response

    @Test("sends report and calls delegate methods with no HTTP response")
    func noHTTPResponse() throws {
        let (reporter, urlSession, backtraceApi, delegate) = try BacktraceReporterTests.makeReporter()
        urlSession.response = MockNoResponse()

        let result = reporter.send(resource: try reporter.generate())
        #expect(result.backtraceStatus == .unknownError)

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledConnectionDidFail)
        #expect(!delegate.calledServerDidRespond)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
        #expect(try reporter.repository.countResources() == 1)
    }

    // MARK: - Given connection error

    @Test("fails to send report and calls delegate methods with connection error")
    func connectionError() throws {
        let (reporter, urlSession, backtraceApi, delegate) = try BacktraceReporterTests.makeReporter()
        urlSession.response = MockConnectionErrorResponse()

        let result = reporter.send(resource: try reporter.generate())
        #expect(result.backtraceStatus == .unknownError)

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledConnectionDidFail)
        #expect(!delegate.calledServerDidRespond)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
        #expect(try reporter.repository.countResources() == 1)
    }

    // MARK: - Given forbidden HTTP response

    @Test("fails to send crash report and calls delegate methods with forbidden HTTP response")
    func forbiddenHTTPResponse() throws {
        let (reporter, urlSession, backtraceApi, delegate) = try BacktraceReporterTests.makeReporter()
        urlSession.response = Mock403Response()

        let result = reporter.send(resource: try reporter.generate())
        #expect(result.backtraceStatus == .serverError)

        #expect(delegate.calledWillSend)
        #expect(delegate.calledWillSendRequest)
        #expect(delegate.calledServerDidRespond)
        #expect(!delegate.calledConnectionDidFail)
        #expect(!delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 1)
        #expect(try reporter.repository.countResources() == 0)
    }

    // MARK: - Given too many reports to send (rate limit)

    @Test("fails and calls limit reached delegate methods when rate limited")
    func rateLimitReached() throws {
        let urlSession = URLSessionMock()
        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let delegate = BacktraceClientDelegateSpy()
        delegate.clear()
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 0)
        let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                              api: backtraceApi,
                                              dbSettings: BacktraceDatabaseSettings(),
                                              credentials: credentials,
                                              oomMode: .full,
                                              urlSession: urlSession)
        reporter.delegate = delegate

        urlSession.response = MockOkResponse()
        let result = reporter.send(resource: try reporter.generate())
        #expect(result.backtraceStatus == .limitReached)

        #expect(!delegate.calledWillSend)
        #expect(!delegate.calledWillSendRequest)
        #expect(!delegate.calledServerDidRespond)
        #expect(!delegate.calledConnectionDidFail)
        #expect(delegate.calledDidReachLimit)
        #expect(backtraceApi.backtraceRateLimiter.timestamps.count == 0)
        #expect(try reporter.repository.countResources() == 0)
    }

    // MARK: - Modify reports via properties

    @Test("can modify multiple reports via reporter attachments and attributes properties")
    func modifyReportsViaProperties() throws {
        let (reporter, urlSession, backtraceApi, _) = try BacktraceReporterTests.makeReporter()
        let delegate = BacktraceClientDelegateMock()
        let attachmentPaths = [URL(fileURLWithPath: "/path1"), URL(fileURLWithPath: "/path2")]
        reporter.attachments += attachmentPaths
        reporter.attributes = ["a": "b"]

        urlSession.response = MockOkResponse()
        backtraceApi.delegate = delegate

        for _ in 0...5 {
            let backtraceReport = try reporter.generate()
            let result = reporter.send(resource: backtraceReport)

            #expect(result.backtraceStatus == .ok)
            #expect(result.report?.attachmentPaths == attachmentPaths.map(\.path))
            #expect(result.report?.attributes["a"] as? String == "b")
        }
    }

    // MARK: - Modify via willSend callbacks

    @Test("can modify report and request if modified in willSend callbacks")
    func modifyReportViaWillSendCallbacks() throws {
        let (reporter, urlSession, backtraceApi, _) = try BacktraceReporterTests.makeReporter()
        let delegate = BacktraceClientDelegateMock()
        let attachmentPaths = ["path1", "path2"]
        let header = (key: "foo", value: "bar")
        urlSession.response = MockOkResponse()
        backtraceApi.delegate = delegate

        delegate.willSendClosure = { report in
            report.attachmentPaths += attachmentPaths
            report.attributes = ["a": "b"]
            return report
        }

        delegate.willSendRequestClosure = { request in
            var request = request
            request.addValue(header.key, forHTTPHeaderField: header.value)
            return request
        }

        let result = reporter.send(resource: try reporter.generate())

        #expect(result.backtraceStatus == .ok)
        #expect(result.report?.attachmentPaths == attachmentPaths)
        #expect(result.report?.attributes["a"] as? String == "b")

        // Now reset the closures and verify the attributes and attachments disappear
        delegate.willSendClosure = { report in
            return report
        }
        delegate.willSendRequestClosure = { request in
            return request
        }

        let result2 = reporter.send(resource: try reporter.generate())

        #expect(result2.backtraceStatus == .ok)
        #expect(result2.report?.attachmentPaths.isEmpty == true)
        #expect(result2.report?.attributes["a"] == nil)
    }

    // MARK: - Report has app version and session

    @Test("report should have application version and session attributes")
    func reportHasAppVersionAndSession() throws {
        let (reporter, urlSession, backtraceApi, _) = try BacktraceReporterTests.makeReporter()
        let delegate = BacktraceClientDelegateMock()
        let backtraceReport = try reporter.generate()
        urlSession.response = MockOkResponse()
        backtraceApi.delegate = delegate

        delegate.willSendClosure = { report in
            #expect(report.attributes["application.session"] != nil)
            #expect(report.attributes["application.version"] != nil)
            return report
        }

        let result = reporter.send(resource: backtraceReport)

        #expect(result.backtraceStatus == .ok)
        #expect(result.report?.attributes["application.session"] != nil)
        #expect(result.report?.attributes["application.version"] != nil)
    }

    // MARK: - Report has metrics attributes

    @Test("report should have metrics attributes")
    func reportHasMetricsAttributes() throws {
        let (reporter, urlSession, backtraceApi, _) = try BacktraceReporterTests.makeReporter()
        let delegate = BacktraceClientDelegateMock()
        let backtraceReport = try reporter.generate()
        urlSession.response = MockOkResponse()
        backtraceApi.delegate = delegate

        delegate.willSendClosure = { report in
            #expect(report.attributes["application.session"] != nil)
            #expect(report.attributes["application.version"] != nil)
            return report
        }

        let result = reporter.send(resource: backtraceReport)

        #expect(result.backtraceStatus == .ok)
        #expect(result.report?.attributes["application.session"] != nil)
        #expect(result.report?.attributes["application.version"] != nil)
    }

    // MARK: - Breadcrumbs attributes (platform-specific)

#if os(iOS) && !targetEnvironment(macCatalyst)
    @Test("report should have breadcrumbs attributes if breadcrumbs is enabled")
    func reportHasBreadcrumbsAttributesWhenEnabled() throws {
        let (reporter, urlSession, backtraceApi, _) = try BacktraceReporterTests.makeReporter()
        let breadcrumbs = BacktraceBreadcrumbs()
        breadcrumbs.enableBreadcrumbs()

        let delegate = BacktraceClientDelegateMock()
        let backtraceReport = try reporter.generate()
        urlSession.response = MockOkResponse()
        backtraceApi.delegate = delegate

        delegate.willSendClosure = { report in
            #expect(report.attributes["breadcrumbs.lastId"] != nil)
            #expect(report.attachmentPaths.first?.contains("bt-breadcrumbs-0") == true)
            return report
        }

        let result = reporter.send(resource: backtraceReport)

        #expect(result.backtraceStatus == .ok)
        #expect(result.report?.attributes["breadcrumbs.lastId"] != nil)
        #expect(result.report?.attachmentPaths.first?.contains("bt-breadcrumbs-0") == true)

        breadcrumbs.disableBreadcrumbs()
    }

    @Test("report should NOT have breadcrumbs attributes if breadcrumbs is NOT enabled")
    func reportDoesNotHaveBreadcrumbsAttributesWhenDisabled() throws {
        let (reporter, urlSession, backtraceApi, _) = try BacktraceReporterTests.makeReporter()
        _ = BacktraceBreadcrumbs()

        let delegate = BacktraceClientDelegateMock()
        let backtraceReport = try reporter.generate()
        urlSession.response = MockOkResponse()
        backtraceApi.delegate = delegate

        delegate.willSendClosure = { report in
            #expect(report.attributes["breadcrumbs.lastId"] == nil)
            #expect(report.attachmentPaths.first == nil)
            return report
        }

        let result = reporter.send(resource: backtraceReport)

        #expect(result.backtraceStatus == .ok)
        #expect(result.report?.attributes["breadcrumbs.lastId"] == nil)
        #expect(result.report?.attachmentPaths.first == nil)
    }
#endif
}

// swiftlint:enable function_body_length force_try
