import XCTest

import Nimble
import Quick
@testable import Backtrace

final class ReportingPolicyTests: QuickSpec {
    override func spec() {
        describe("Reporting Policy") {
            throwingContext("given valid credentials") {
                let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!,
                                                       token: "")

                context("policy allows debugger attachment") {
                    let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                                     allowsAttachingDebugger: true)
                    context("the debugger is attached") {
                        it("can report") {
                            expect(ReportingPolicy(configuration: configuration,
                                                   debuggerChecker: AttachedDebuggerCheckerMock.self).allowsReporting)
                                .to(beTrue())
                        }
                    }

                    context("the debugger is not attached") {
                        it("can report") {
                            expect(ReportingPolicy(configuration: configuration,
                                                   debuggerChecker: DetachedDebuggerCheckerMock.self).allowsReporting)
                                .to(beTrue())
                        }
                    }
                }

                context("policy disallows debugger attachment") {
                    let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                                     allowsAttachingDebugger: false)
                    context("the debugger is attached") {
                        it("cannot report") {
                            expect(ReportingPolicy(configuration: configuration,
                                                   debuggerChecker: AttachedDebuggerCheckerMock.self).allowsReporting)
                                .to(beFalse())
                        }
                    }

                    context("the debugger is not attached") {
                        it("can report") {
                            expect(ReportingPolicy(configuration: configuration,
                                                   debuggerChecker: DetachedDebuggerCheckerMock.self).allowsReporting)
                                .to(beTrue())
                        }
                    }
                }
            }
        }
    }
}
