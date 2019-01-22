import Nimble
import Quick
@testable import Backtrace

final class BacktraceIntegrationTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            it("generates live report", closure: {
                expect { try crashReporter.generateLiveReport() }
                    .toNot(throwError())
            })
            it("generate live report 100 times", closure: {
                for _ in 0...100 {
                    expect{ try crashReporter.generateLiveReport() }
                        .toNot(throwError())
                }
            })
            
            describe("Backtrace API") {
                describe("Valid credentials", closure: {
                    var networkClientWithValidCredentials: BacktraceNetworkClient {
                        let endpoint = URL(string: "https://yolo.sp.backtrace.io:6098")!
                        let token = "b06c6083414bf7b8e200ad994c9c8ea5d6c8fa747b6608f821278c48a4d408c3"
                        return BacktraceNetworkClient(endpoint: endpoint, token: token)
                    }
                    it("sends crash report", closure: {
                        expect { try networkClientWithValidCredentials.send(try crashReporter.generateLiveReport().reportData)}
                            .toNotEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Crash report should be successfully sent.")
                    })
                    it("sends crash report", closure: {
                        let error = HttpError.unknownError
                        let registeredClient = BacktraceRegisteredClient(networkClient: networkClientWithValidCredentials)
                        expect { try registeredClient.send(error).status }
                            .toEventually(equal(.ok), timeout: 10, pollInterval: 0.5, description: "Should succeed to send a crash report")
                    })
                })
                describe("Invalid endpoint", closure: {
                    var networkClientWithInvalidEndpoint: BacktraceNetworkClient {
                        let invalidEndpoint = URL(string: "https://not.exist.yolo.sp.backtrace.io:6098")!
                        let token = "b06c6083414bf7b8e200ad994c9c8ea5d6c8fa747b6608f821278c48a4d408c3"
                        return BacktraceNetworkClient(endpoint: invalidEndpoint, token: token)
                    }
                    it("fails to send crash report with invalid endpoint", closure: {
                        expect { try networkClientWithInvalidEndpoint.send(try crashReporter.generateLiveReport().reportData)}
                            .toEventually(throwError())
                    })
                    it("throws error while trying to send crash report", closure: {
                        let error = HttpError.unknownError
                        let registeredClient = BacktraceRegisteredClient(networkClient: networkClientWithInvalidEndpoint)
                        expect { try registeredClient.send(error) }
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Should fail to send a crash report")
                    })
                })
                describe("Invalid token", closure: {
                    var networkClientWithInvalidToken: BacktraceNetworkClient {
                        let endpoint = URL(string: "https://yolo.sp.backtrace.io:6098")!
                        let invalidToken = "ba89a7a66b67f78c989c6aba89a7a66b67f78c989c6a"
                        return BacktraceNetworkClient(endpoint: endpoint, token: invalidToken)
                    }
                    it("fails to send crash report with invalid token", closure: {
                        expect { try networkClientWithInvalidToken.send(try crashReporter.generateLiveReport().reportData)}
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Status code should be 403 - Forbidden.")
                    })
                    it("throws error while trying to send crash report", closure: {
                        let error = HttpError.unknownError
                        let registeredClient = BacktraceRegisteredClient(networkClient: networkClientWithInvalidToken)
                        expect { try registeredClient.send(error) }
                            .toEventually(throwError(), timeout: 10, pollInterval: 0.5, description: "Should fail to send a crash report")
                    })
                })
            }
        }
    }
}
