import Foundation

struct ReportingPolicy {
    let configuration: BacktraceClientConfiguration
    let debuggerChecker: DebuggerChecking.Type

    init(configuration: BacktraceClientConfiguration, debuggerChecker: DebuggerChecking.Type = DebuggerChecker.self) {
        self.configuration = configuration
        self.debuggerChecker = debuggerChecker
    }

    var allowsReporting: Bool {
        //  iSDebugger / allowsDebugger |   0   |   1
        //                          0   |   1   |   1
        //                          1   |   0   |   1
        //
        return !debuggerChecker.isAttached() || configuration.allowsAttachingDebugger
    }
}
