import Nimble
import Quick
@testable import Backtrace

final class BacktraceTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            context("given valid configuration") {
                it("generates live report on demand", closure: {
                    expect { try crashReporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                })
                it("generate live report on demand 10 times", closure: {
                    for _ in 0...10 {
                        expect { try crashReporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                    }
                })
            }
            
            describe("Backtrace API") {
                let urlSession = URLSessionMock()
                urlSession.response = MockOkResponse(url: URL(string: "https://yourteam.backtrace.io")!)
                let credentials =
                    BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
                let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                
                context("given valid credentials", closure: {
                    
                    it("sends crash report", closure: {
                        urlSession.response = MockOkResponse(url: URL(string: "https://yourteam.backtrace.io")!)
                        expect { try backtraceApi
                            .send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .toNotEventually(throwError(), timeout: 10, pollInterval: 0.5)
                    })
                })
                context("given invalid endpoint", closure: {
                    it("fails to send crash report with invalid endpoint", closure: {
                        urlSession.response = MockNoResponse()
                        expect { try backtraceApi
                            .send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .toEventually(throwError())
                    })
                    
                    it("throws error while trying to send crash report", closure: {
                        urlSession.response = MockNoResponse()
                        expect { try BacktraceReporter(reporter: crashReporter, api: backtraceApi,
                                                       dbSettings: BacktraceDatabaseSettings(),
                                                       credentials: credentials).send() }
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5)
                    })
                })
                context("given invalid token", closure: {
                    it("fails to send crash report with invalid token", closure: {
                        urlSession.response = Mock403Response(url: URL(string: "https://yourteam.backtrace.io")!)
                        expect {
                            let report = try crashReporter.generateLiveReport(attributes: [:])
                            return try backtraceApi.send(report).backtraceStatus
                            }
                            .toEventually(equal(BacktraceReportStatus.serverError), timeout: 10, pollInterval: 0.5,
                                          description: "Status code should be 403 - Forbidden.")
                    })
                })
            }
        }
    }
}
