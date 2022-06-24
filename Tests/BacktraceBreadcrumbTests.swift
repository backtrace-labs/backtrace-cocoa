import XCTest
import Nimble
import Quick

@testable import Backtrace

final class BacktraceBreadcrumbTests: QuickSpec {
    
    override func spec() {
        describe("Breadcrumbs") {
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let dbSettings = BacktraceDatabaseSettings()
            let reportsPerMin = 3
            var configuration: BacktraceClientConfiguration?

            beforeEach {
                configuration = BacktraceClientConfiguration(credentials: credentials, dbSettings: dbSettings,
                                                                 reportsPerMin: reportsPerMin)
            }
            afterEach {
                configuration = nil
            }
            context("breadcrumb is not enabled") {
                it("fails to add breadcrumb") {
                    let result = configuration?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beFalse())
                }
            }
            context("breadcrumb is enabled") {
                it("Able to add breadcrumb") {
                    configuration?.enableBreadCrumbs()
                    let result = configuration?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beTrue())
                }
            }
            
            context("breadcrumb is enabled") {
                throwingIt("report should have breadcrumb attributes and path if breadcrumb is enabled") {
                    configuration?.enableBreadCrumbs()
                    
                    let breadcrumb = BacktraceBreadcrumb()
                    breadcrumb.enableBreadCrumbs()
                    let _ = breadcrumb.addBreadcrumb("Breadcrumb submission test")
                    
                    let urlSession = URLSessionMock()
                    let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                    let delegate = BacktraceClientDelegateMock()
                    let reporter = try! BacktraceReporter(reporter: BacktraceCrashReporter(),
                                                          api: backtraceApi,
                                                          dbSettings: BacktraceDatabaseSettings(),
                                                          credentials: credentials,
                                                          urlSession: urlSession)
                    var backtraceReport = try reporter.generate()
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate
                    
                    breadcrumb.processReportBreadcrumbs(&backtraceReport)
                    
                    let result = reporter.send(resource: backtraceReport)

                    let breadCrumbPath =  result.report?.attachmentPaths.first(where: {
                        $0.contains("bt-breadcrumbs-0")
                    })
                    expect { breadCrumbPath }.toNot(beNil())
                    expect { result.report?.attributes["breadcrumbs.lastId"] }.toNot(beNil())
                }
            }
        }
    }
}
