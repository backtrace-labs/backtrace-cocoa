import Nimble
import Quick
@testable import Backtrace

final class BacktraceTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            it("generates live report", closure: {
                expect { try crashReporter.generateLiveReport(attributes: [:]) }
                    .toNot(throwError())
            })
            it("generate live report 10 times", closure: {
                for _ in 0...10 {
                    expect { try crashReporter.generateLiveReport(attributes: [:]) }
                        .toNot(throwError())
                }
            })
            
            describe("Backtrace API") {
                context("has valid credentials", closure: {
                    var networkClientWithValidCredentials: BacktraceApiProtocol {
                        return BacktraceApiMock(config: .validCredentials)
                    }
                    it("sends crash report", closure: {
                        expect { try networkClientWithValidCredentials
                            .send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .toNotEventually(throwError(), timeout: 10, pollInterval: 0.5)
                    })
                })
                context("has invalid endpoint", closure: {
                    var networkClientWithInvalidEndpoint: BacktraceApiProtocol {
                        return BacktraceApiMock(config: .invalidEndpoint)
                    }
                    it("fails to send crash report with invalid endpoint", closure: {
                        expect { try networkClientWithInvalidEndpoint
                            .send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .toEventually(throwError())
                    })
                    it("throws error while trying to send crash report", closure: {
                        let error = HttpError.unknownError
                        expect { try BacktraceReporter(reporter: crashReporter, api: networkClientWithInvalidEndpoint,
                                                       dbSettings: BacktraceDatabaseSettings(),
                                                       reportsPerMin: 3).send() }
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5)
                    })
                })
                context("has invalid token", closure: {
                    var networkClientWithInvalidToken: BacktraceApiProtocol {
                        return BacktraceApiMock(config: .invalidToken)
                    }
                    it("fails to send crash report with invalid token", closure: {
                        expect {
                            let report = try crashReporter.generateLiveReport(attributes: [:])
                            return try networkClientWithInvalidToken.send(report).backtraceStatus
                            }
                            .toEventually(equal(BacktraceReportStatus.serverError), timeout: 10, pollInterval: 0.5,
                                          description: "Status code should be 403 - Forbidden.")
                    })
                })
            }
        }
    }
}
