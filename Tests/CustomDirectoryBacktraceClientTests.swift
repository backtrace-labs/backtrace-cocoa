import Foundation
import Testing

@testable import Backtrace
@preconcurrency import CrashReporter

@Suite("Custom crash directory")
struct CustomDirectoryBacktraceClientTests {

    // MARK: - Helpers

    private func createCustomDirAndProtectionType() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = baseURL.appendingPathComponent("crash-directory-spec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.none]
        )
        return dir
    }

    private func makeSetup() throws -> (customDir: URL, credentials: BacktraceCredentials,
                                         clientConfig: BacktraceClientConfiguration,
                                         basePathConfig: PLCrashReporterConfig) {
        let customDir = try createCustomDirAndProtectionType()
        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let clientConfig = BacktraceClientConfiguration(credentials: credentials)
        guard let basePathConfig = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all, basePath: customDir.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return (customDir, credentials, clientConfig, basePathConfig)
    }

    // MARK: - Tests

    @Test("Creates a valid PLCrashReporterConfig with a custom basePath")
    func createsValidPLCrashReporterConfig() throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.customDir) }

        #expect(setup.basePathConfig != nil)
    }

    @Test("Initializes BacktraceCrashReporter without throwing")
    func initializesBacktraceCrashReporterWithoutThrowing() throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.customDir) }

        #expect(throws: Never.self) {
            _ = BacktraceCrashReporter(config: setup.basePathConfig)
        }
    }

    @Test("Initializes BacktraceClient with BacktraceCrashReporter")
    func initializesBacktraceClientWithCrashReporter() throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.customDir) }

        let reporter = BacktraceCrashReporter(config: setup.basePathConfig)
        var client: BacktraceClient!
        #expect(throws: Never.self) {
            client = try BacktraceClient(configuration: setup.clientConfig, crashReporter: reporter)
        }

        BacktraceClient.shared = client
        #expect(BacktraceClient.shared === client)
    }

#if !targetEnvironment(simulator) && !os(macOS) && !targetEnvironment(macCatalyst)
    @Test("Enables PLCrashReporter without error and respects file protection")
    func respectsFileProtection() throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.customDir) }

        _ = BacktraceCrashReporter(config: setup.basePathConfig)

        let attributes = try? FileManager.default.attributesOfItem(atPath: setup.customDir.path)
        let protection = attributes?[.protectionKey] as? FileProtectionType
        #expect(protection == FileProtectionType.none, "Expected file protection to match input (.none).")
    }
#endif

    @Test("Generates a live report without error")
    func generatesLiveReportWithoutError() throws {
        let setup = try makeSetup()
        defer { try? FileManager.default.removeItem(at: setup.customDir) }

        let reporter = BacktraceCrashReporter(config: setup.basePathConfig)

        #expect(throws: Never.self) {
            _ = try reporter.generateLiveReport(attributes: ["foo": "bar"])
        }
    }
}
