import XCTest

import Nimble
import Quick
@testable import Backtrace

final class ReportingPolicyTests: QuickSpec {
    override func spec() {
        describe("ReportingPolicy") {
            throwingContext("Valid credentials", closure: {
                guard let endpoint = URL(string: "https://wwww.backtrace.io") else { fail(); return }
                let token = "token"
                let credentials = BacktraceCredentials(endpoint: endpoint, token: token)
                context("Allows reporting when debugger is attached", closure: {
                    let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                                     allowsAttachingDebugger: true)
                    it("has attached debugger", closure: {
                        expect(ReportingPolicy(configuration: configuration,
                                               debuggerChecker: AttachedDebuggerCheckerMock.self).allowsReporting)
                            .to(beTrue())
                    })
                    it("has no debugger attached", closure: {
                        expect(ReportingPolicy(configuration: configuration,
                                               debuggerChecker: DetachedDebuggerCheckerMock.self).allowsReporting)
                            .to(beTrue())
                    })
                })
                
                context("Disallows reporting when debugger is attached", closure: {
                    let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                                     allowsAttachingDebugger: false)
                    it("has attached debugger", closure: {
                        expect(ReportingPolicy(configuration: configuration,
                                               debuggerChecker: AttachedDebuggerCheckerMock.self).allowsReporting)
                            .to(beFalse())
                    })
                    it("has no debugger attached", closure: {
                        expect(ReportingPolicy(configuration: configuration,
                                               debuggerChecker: DetachedDebuggerCheckerMock.self).allowsReporting)
                            .to(beTrue())
                    })
                })
            })
        }
    }
}
