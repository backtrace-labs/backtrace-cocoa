import Quick
import Nimble
@testable import Backtrace
@testable import CrashReporter

final class CustomDirectoryBacktraceClientTests: QuickSpec {
    override func spec() {
        
        describe("Custom crash directory") {
            
            var customDir: URL!
            var credentials: BacktraceCredentials!
            var backtraceClientConfiguration: BacktraceClientConfiguration!
            var basePathConfig: PLCrashReporterConfig!
            
            beforeEach {
                customDir = try! self.createCustomDirAndProtectionType()
                credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
                backtraceClientConfiguration = BacktraceClientConfiguration(credentials: credentials)
                basePathConfig = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all, basePath: customDir.path)
            }
            
            afterEach {
                try? FileManager.default.removeItem(at: customDir)
            }
            
            it("creates a valid PLCrashReporterConfig with a custom basePath") {
                expect(basePathConfig).toNot(beNil())
            }
            
            it("initializes BacktraceCrashReporter without throwing") {
                expect { _ = BacktraceCrashReporter(config: basePathConfig) }.toNot(throwError())
            }
            
            it("initializes BacktraceClient with BacktraceCrashReporte") {
                let reporter = BacktraceCrashReporter(config: basePathConfig)
                var client: BacktraceClient!
                expect {client = try BacktraceClient(configuration: backtraceClientConfiguration,crashReporter: reporter)}.toNot(throwError())
                
                BacktraceClient.shared = client
                expect(BacktraceClient.shared).to(be(client))
            }
            
            describe("enabled reporter behavior") {
                var reporter: BacktraceCrashReporter!
                
                beforeEach {
                    reporter = BacktraceCrashReporter(config: basePathConfig)
                }
                
#if !targetEnvironment(simulator)
                it("enables PLCrashReporter without error and respects file protection") {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: customDir.path)
                    let protection = attributes?[.protectionKey] as? FileProtectionType
                    expect(protection).to(equal(FileProtectionType.none), description: "Expected file protection to match input (.none).")
                }
#endif
                
                it("generates a live report without error") {
                    expect { _ = try reporter.generateLiveReport(attributes: ["foo": "bar"]) }.toNot(throwError())
                }
            }
        }
    }
    
    // MARK: – Helpers
    
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
}
