import Foundation
import Testing
@preconcurrency import CrashReporter

@testable import Backtrace

@Suite struct BacktraceReporterThreadSpec {

    // MARK: - Setup helper

    private static func makeReporter() throws -> (backtraceReporter: BacktraceReporter, mockPLCR: PLCrashReporterMock) {
        let credentials = BacktraceCredentials(
            endpoint: URL(string: "https://example.backtrace.io")!,
            token: ""
        )
        let urlSession = URLSessionMock()
        let mockPLCR = PLCrashReporterMock()

        let crashReporter = BacktraceCrashReporter(reporter: mockPLCR)

        let api = BacktraceApi(
            credentials: credentials,
            session: urlSession,
            reportsPerMin: 30
        )

        let backtraceReporter = try BacktraceReporter(
            reporter: crashReporter,
            api: api,
            dbSettings: BacktraceDatabaseSettings(),
            credentials: credentials,
            oomMode: .full,
            urlSession: urlSession
        )

        return (backtraceReporter, mockPLCR)
    }

    // MARK: - Thread-aware live-report capture

    @Test("passes the calling thread to PLCrashReporter")
    func passesCallingThreadToPLCrashReporter() throws {
        let (backtraceReporter, mockPLCR) = try BacktraceReporterThreadSpec.makeReporter()

        let callThread = mach_thread_self()
        _ = try? backtraceReporter.generate()
        #expect(mockPLCR.lastThread == callThread)
        mach_port_deallocate(currentTaskPort(), callThread)
    }

    @Test("does not leak Mach SEND rights (> 2 refs to cover noise)")
    func doesNotLeakMachSendRights() throws {
        let (backtraceReporter, _) = try BacktraceReporterThreadSpec.makeReporter()

        let before = BacktraceReporterThreadSpec.sendRefCount()
        _ = try? backtraceReporter.generate()
        let after = BacktraceReporterThreadSpec.sendRefCount()
        #expect(after <= before + 2)
    }

    // MARK: - Helpers

    /// Current ref-count for thread (properly deallocates the port returned by mach_thread_self)
    private static func sendRefCount() -> mach_port_urefs_t {
        let thread = mach_thread_self()
        var refs: mach_port_urefs_t = 0
        mach_port_get_refs(
            currentTaskPort(),
            thread,
            MACH_PORT_RIGHT_SEND,
            &refs
        )
        mach_port_deallocate(currentTaskPort(), thread)
        return refs
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
