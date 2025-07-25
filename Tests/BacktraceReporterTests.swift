import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceReporterTests: QuickSpec {
    // swiftlint:disable function_body_length force_try
    override func spec() {
        describe("Backtrace reporter") {
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            var backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
            let delegate = BacktraceClientDelegateSpy()
            var reporter = try! BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                  api: backtraceApi,
                                                  dbSettings: BacktraceDatabaseSettings(),
                                                  credentials: credentials,
                                                  oomMode: .full,
                                                  urlSession: urlSession)

            throwingBeforeEach {
                delegate.clear()
                backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                 api: backtraceApi,
                                                 dbSettings: BacktraceDatabaseSettings(),
                                                 credentials: credentials,
                                                 oomMode: .full,
                                                 urlSession: urlSession)
                try reporter.repository.clear()
                reporter.delegate = delegate
            }

            context("given valid HTTP response") {
                it("sends report and calls delegate methods") {
                    urlSession.response = MockOkResponse()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.ok))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(0))
                }
            }
            context("given no HTTP response") {
                it("sends report and calls delegate methods") {
                    urlSession.response = MockNoResponse()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.unknownError))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(1))
                }
            }

            context("given connection error") {
                it("fails to send report and calls delegate methods") {
                    urlSession.response =
                        MockConnectionErrorResponse()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.unknownError))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(1))
                }
            }

            context("given forbidden HTTP response") {
                it("fails to send crash report and calls delegate methods") {
                    urlSession.response = Mock403Response()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.serverError))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                    expect { try reporter.repository.countResources() }.to(equal(0))
                }
            }

            context("given too many reports to send") {
                throwingIt("fails and calls limit reached delegate methods") {
                    backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 0)
                    reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                     api: backtraceApi,
                                                     dbSettings: BacktraceDatabaseSettings(),
                                                     credentials: credentials,
                                                     oomMode: .full,
                                                     urlSession: urlSession)
                    reporter.delegate = delegate

                    urlSession.response = MockOkResponse()
                    expect { reporter.send(resource: try reporter.generate()).backtraceStatus }
                        .to(equal(.limitReached))

                    expect { delegate.calledWillSend }.to(beFalse())
                    expect { delegate.calledWillSendRequest }.to(beFalse())
                    expect { delegate.calledServerDidRespond }.to(beFalse())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beTrue())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(0))
                    expect { try reporter.repository.countResources() }.to(equal(0))
                }
            }

            context("given new report") {
                throwingIt("can modify multiple reports via reporter attachments and attributes properties") {
                    let delegate = BacktraceClientDelegateMock()
                    let attachmentPaths = [URL(fileURLWithPath: "/path1"), URL(fileURLWithPath: "/path2")]
                    reporter.attachments += attachmentPaths
                    reporter.attributes = ["a": "b"]

                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    for _ in 0...5 {
                        let backtraceReport = try reporter.generate()
                        let result = reporter.send(resource: backtraceReport)

                        expect { result.backtraceStatus }.to(equal(.ok))
                        expect { result.report?.attachmentPaths }.to(equal(attachmentPaths.map(\.path)))
                        expect { result.report?.attributes["a"] as? String }.to(equal("b"))
                    }
                }

                throwingIt("can modify report and request if modified in willSend callbacks") {
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

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attachmentPaths }.to(equal(attachmentPaths))
                    expect { result.report?.attributes["a"] as? String }.to(equal("b"))

                    // Now result the closures and verify the attributes and attachments disappear
                    delegate.willSendClosure = { report in
                        return report
                    }
                    delegate.willSendRequestClosure = { request in
                        return request
                    }

                    let result2 = reporter.send(resource: try reporter.generate())

                    expect { result2.backtraceStatus }.to(equal(.ok))
                    expect { result2.report?.attachmentPaths }.to(beEmpty())
                    expect { result2.report?.attributes["a"] }.to(beNil())
                }

                it("report should have application version and session attributes") {
                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["application.session"] }.notTo(beNil())
                        expect { report.attributes["application.version"] }.notTo(beNil())
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["application.session"] }.notTo(beNil())
                    expect { result.report?.attributes["application.version"] }.notTo(beNil())
                }

                it("report should have metrics attributes") {
                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["application.session"] }.toNot(beNil())
                        expect { report.attributes["application.version"] }.toNot(beNil())
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["application.session"] }.toNot(beNil())
                    expect { result.report?.attributes["application.version"] }.toNot(beNil())
                }
#if os(iOS) && !targetEnvironment(macCatalyst)
                it("report should have breadcrumbs attributes if breadcrumbs is enabled") {
                    let breadcrumbs = BacktraceBreadcrumbs()
                    breadcrumbs.enableBreadcrumbs()

                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["breadcrumbs.lastId"] }.toNot(beNil())
                        expect { report.attachmentPaths.first }.to(contain("bt-breadcrumbs-0"))
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["breadcrumbs.lastId"] }.toNot(beNil())
                    expect { result.report?.attachmentPaths.first }.to(contain("bt-breadcrumbs-0"))

                    breadcrumbs.disableBreadcrumbs()
                }

                it("report should NOT have breadcrumbs attributes if breadcrumbs is NOT enabled") {
                    _ = BacktraceBreadcrumbs()

                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["breadcrumbs.lastId"] }.to(beNil())
                        expect { report.attachmentPaths.first }.to(beNil())
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["breadcrumbs.lastId"] }.to(beNil())
                    expect { result.report?.attachmentPaths.first }.to(beNil())
                }
#endif
            }
        }
    }
    // swiftlint:enable function_body_length force_try
}
