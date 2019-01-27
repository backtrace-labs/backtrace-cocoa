import Nimble
import Quick
@testable import Backtrace

final class BacktraceTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            it("generates live report", closure: {
                expect { try crashReporter.generateLiveReport() }
                    .toNot(throwError())
            })
            it("generate live report 10 times", closure: {
                for _ in 0...10 {
                    expect{ try crashReporter.generateLiveReport() }
                        .toNot(throwError())
                }
            })
            
            describe("Backtrace API") {
                describe("Valid credentials", closure: {
                    var networkClientWithValidCredentials: NetworkClientType {
                        return BacktraceNetworkClientMock(config: .validCredentials)
                    }
                    it("sends crash report", closure: {
                        expect { try networkClientWithValidCredentials.send(try crashReporter.generateLiveReport().reportData)}
                            .toNotEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Crash report should be successfully sent.")
                    })
                    it("sends crash report", closure: {
                        expect { try BacktraceRegisteredClient(networkClient: networkClientWithValidCredentials, dbSettings: BacktraceDatabaseSettings()).send().description }
                            .toEventually(equal(BacktraceResult(.ok(response: "Ok.")).description), timeout: 10, pollInterval: 0.5, description: "Should succeed to send a crash report")
                    })
                })
                describe("Invalid endpoint", closure: {
                    var networkClientWithInvalidEndpoint: NetworkClientType {
                        return BacktraceNetworkClientMock(config: .invalidEndpoint)
                    }
                    it("fails to send crash report with invalid endpoint", closure: {
                        expect { try networkClientWithInvalidEndpoint.send(try crashReporter.generateLiveReport().reportData)}
                            .toEventually(throwError())
                    })
                    it("throws error while trying to send crash report", closure: {
                        let error = HttpError.unknownError
                        expect { try BacktraceRegisteredClient(networkClient: networkClientWithInvalidEndpoint, dbSettings: BacktraceDatabaseSettings()).send() }
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Should fail to send a crash report")
                    })
                })
                describe("Invalid token", closure: {
                    var networkClientWithInvalidToken: NetworkClientType {
                        return BacktraceNetworkClientMock(config: .invalidToken)
                    }
                    it("fails to send crash report with invalid token", closure: {
                        expect { try networkClientWithInvalidToken.send(try crashReporter.generateLiveReport().reportData)}
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Status code should be 403 - Forbidden.")
                    })
                    it("throws error while trying to send crash report", closure: {
                        expect { try BacktraceRegisteredClient(networkClient: networkClientWithInvalidToken, dbSettings: BacktraceDatabaseSettings()).send() }
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Should fail to send a crash report")
                    })
                })
            }
        }
    }
}
