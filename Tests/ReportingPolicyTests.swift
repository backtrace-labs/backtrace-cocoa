import Testing
@testable import Backtrace
import Foundation

@Suite("Reporting Policy")
struct ReportingPolicyTests {

    let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!,
                                           token: "")

    // MARK: - Policy allows debugger attachment

    @Test("Allows reporting when policy allows debugger attachment and debugger is attached")
    func allowsReportingWhenPolicyAllowsDebuggerAndDebuggerIsAttached() {
        let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                         allowsAttachingDebugger: true)
        let policy = ReportingPolicy(configuration: configuration,
                                     debuggerChecker: AttachedDebuggerCheckerMock.self)
        #expect(policy.allowsReporting)
    }

    @Test("Allows reporting when policy allows debugger attachment and debugger is not attached")
    func allowsReportingWhenPolicyAllowsDebuggerAndDebuggerIsNotAttached() {
        let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                         allowsAttachingDebugger: true)
        let policy = ReportingPolicy(configuration: configuration,
                                     debuggerChecker: DetachedDebuggerCheckerMock.self)
        #expect(policy.allowsReporting)
    }

    // MARK: - Policy disallows debugger attachment

    @Test("Cannot report when policy disallows debugger attachment and debugger is attached")
    func cannotReportWhenPolicyDisallowsDebuggerAndDebuggerIsAttached() {
        let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                         allowsAttachingDebugger: false)
        let policy = ReportingPolicy(configuration: configuration,
                                     debuggerChecker: AttachedDebuggerCheckerMock.self)
        #expect(!policy.allowsReporting)
    }

    @Test("Allows reporting when policy disallows debugger attachment and debugger is not attached")
    func allowsReportingWhenPolicyDisallowsDebuggerAndDebuggerIsNotAttached() {
        let configuration = BacktraceClientConfiguration(credentials: credentials,
                                                         allowsAttachingDebugger: false)
        let policy = ReportingPolicy(configuration: configuration,
                                     debuggerChecker: DetachedDebuggerCheckerMock.self)
        #expect(policy.allowsReporting)
    }
}
