import Quick
import Nimble
import CrashReporter
@testable import Backtrace

final class BacktraceReporterThreadSpec: QuickSpec {
    
    override func spec() {
        
        describe("Thread-aware live-report capture") {
            
            var backtraceReporter: BacktraceReporter!
            var mockPLCR: PLCrashReporterMock!
            var urlSession: URLSessionMock!
            var credentials: BacktraceCredentials!
            
            beforeEach {
                credentials = BacktraceCredentials(
                    endpoint: URL(string: "https://example.backtrace.io")!,
                    token: ""
                )
                urlSession = URLSessionMock()
                mockPLCR   = PLCrashReporterMock()
                
                let crashReporter = BacktraceCrashReporter(reporter: mockPLCR)
                
                let api = BacktraceApi(
                    credentials: credentials,
                    session: urlSession,
                    reportsPerMin: 30
                )
                
                backtraceReporter = try! BacktraceReporter(
                    reporter: crashReporter,
                    api: api,
                    dbSettings: BacktraceDatabaseSettings(),
                    credentials: credentials,
                    urlSession: urlSession
                )
            }
            
            it("passes the calling thread to PLCrashReporter") {
                let callThread = mach_thread_self()
                _ = try? backtraceReporter.generate()
                expect(mockPLCR.lastThread).to(equal(callThread))
                mach_port_deallocate(mach_task_self_, callThread)
            }
            
            it("does not leak Mach SEND rights (> 2 refs to cover noise from Quick/Nimble or XCTest)") {
                let before = sendRefCount()
                _ = try? backtraceReporter.generate()
                let after  = sendRefCount()
                expect(after).to(beLessThanOrEqualTo(before + 2))
            }
        }
    }
}

/// Mock PLCrashReporter stubs that records the thread parameter
private final class PLCrashReporterMock: PLCrashReporter {
    
    private(set) var lastThread: thread_t = mach_thread_self()
    
    override func generateLiveReport(
        withThread thread: thread_t,
        exception: NSException?
    ) throws -> Data {
        lastThread = thread
        return Data([0xCA, 0xFE])
    }
    
    override func generateLiveReport(with exception: NSException?) throws -> Data {
        return Data([0xBE, 0xEF])
    }
}

/// Current ref-count for thread
private func sendRefCount() -> mach_port_urefs_t {
    var refs: mach_port_urefs_t = 0
    mach_port_get_refs(
        mach_task_self_,
        mach_thread_self(),
        MACH_PORT_RIGHT_SEND,
        &refs
    )
    return refs
}
