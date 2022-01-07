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
                                                  urlSession: urlSession)

            throwingBeforeEach {
                delegate.clear()
                backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                 api: backtraceApi,
                                                 dbSettings: BacktraceDatabaseSettings(),
                                                 credentials: credentials,
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    expect { try reporter.repository.countResources() }.to(be(0))
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    expect { try reporter.repository.countResources() }.to(be(1))
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    expect { try reporter.repository.countResources() }.to(be(1))
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    expect { try reporter.repository.countResources() }.to(be(0))
                }
            }

            context("given too many reports to send") {
                throwingIt("fails and calls limit reached delegate methods") {
                    backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 0)
                    reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                     api: backtraceApi,
                                                     dbSettings: BacktraceDatabaseSettings(),
                                                     credentials: credentials,
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(0))
                    expect { try reporter.repository.countResources() }.to(be(0))
                }
            }

            context("given new report") {
                throwingIt("can modify the report") {
                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    let attachmentPaths = ["path1", "path2"]
                    let header = (key: "foo", value: "bar")
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        report.attachmentPaths = attachmentPaths
                        return report
                    }

                    delegate.willSendRequestClosure = { request in
                        var request = request
                        request.addValue(header.key, forHTTPHeaderField: header.value)
                        return request
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attachmentPaths }.to(equal(attachmentPaths))
                }

                throwingIt("report should NOT have metrics attributes if metrics is NOT enabled") {
                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        expect { report.attributes["application.session"] }.to(beNil())
                        expect { report.attributes["application.version"] }.to(beNil())
                        return report
                    }

                    let result = reporter.send(resource: backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attributes["application.session"] }.to(beNil())
                    expect { result.report?.attributes["application.version"] }.to(beNil())
                }

                throwingIt("report should have metrics attributes if metrics is enabled") {
                    let metrics = BacktraceMetrics(api: backtraceApi)
                    metrics.enable(settings: BacktraceMetricsSettings())

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

                    MetricsInfo.disableMetrics()
                }
            }
        }
    }
    // swiftlint:enable function_body_length force_try
}
