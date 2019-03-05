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
                    expect{ try crashReporter.generateLiveReport(attributes: [:]) }
                        .toNot(throwError())
                }
            })
            
            describe("Backtrace API") {
                describe("Valid credentials", closure: {
                    var networkClientWithValidCredentials: BacktraceApiProtocol {
                        return BacktraceNetworkClientMock(config: .validCredentials)
                    }
                    it("sends crash report", closure: {
                        expect { try networkClientWithValidCredentials.send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .toNotEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Crash report should be successfully sent.")
                    })
                })
                describe("Invalid endpoint", closure: {
                    var networkClientWithInvalidEndpoint: BacktraceApiProtocol {
                        return BacktraceNetworkClientMock(config: .invalidEndpoint)
                    }
                    it("fails to send crash report with invalid endpoint", closure: {
                        expect { try networkClientWithInvalidEndpoint.send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .toEventually(throwError())
                    })
                    it("throws error while trying to send crash report", closure: {
                        let error = HttpError.unknownError
                        expect { try BacktraceReporter(reporter: crashReporter, api: networkClientWithInvalidEndpoint, dbSettings: BacktraceDatabaseSettings(), reportsPerMin: 3).send() }
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Should fail to send a crash report")
                    })
                })
                describe("Invalid token", closure: {
                    var networkClientWithInvalidToken: BacktraceApiProtocol {
                        return BacktraceNetworkClientMock(config: .invalidToken)
                    }
                    it("fails to send crash report with invalid token", closure: {
                        do {
                            let report = try crashReporter.generateLiveReport(attributes: [:])
                            expect { try networkClientWithInvalidToken.send(report).backtraceStatus}
                                .toEventually(equal(BacktraceReportStatus.serverError), timeout: 10, pollInterval: 0.5, description: "Status code should be 403 - Forbidden.")
                        } catch {
                            fail(error.localizedDescription)
                        }
                    })
                })
            }
        }
    }
}
