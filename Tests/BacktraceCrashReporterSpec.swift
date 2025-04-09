import XCTest
import Nimble
import Quick
@testable import Backtrace

final class BacktraceCrashReporterSpec: QuickSpec {
    override func spec() {
        describe("BacktraceCrashReporter") {

            context("when using the new convenience initializer") {
                let fileManager = FileManager.default
                var customDirectory: URL!

                beforeEach {
                    customDirectory = fileManager
                        .temporaryDirectory
                        .appendingPathComponent("bt-test-crash-reporter-\(UUID().uuidString)")
                    try? fileManager.removeItem(at: customDirectory)
                }

                it("creates the custom directory with the specified file protection") {
                    let reporter = BacktraceCrashReporter(
                        crashDirectory: customDirectory,
                        fileProtection: .none,
                        signalHandlerType: .BSD,
                        symbolicationStrategy: .all
                    )

                    var isDir: ObjCBool = false
                    let exists = fileManager.fileExists(atPath: customDirectory.path, isDirectory: &isDir)
                    expect(exists).to(beTrue(), description: "Expected directory to exist.")
                    expect(isDir.boolValue).to(beTrue(), description: "Expected path to be a directory.")

#if !targetEnvironment(simulator)
                    let attributes = try? fileManager.attributesOfItem(atPath: customDirectory.path)
                    let protection = attributes?[.protectionKey] as? FileProtectionType
                    expect(protection).to(equal(FileProtectionType.none), description: "Expected file protection to match input (.none).")
#endif

                    expect { try reporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                }

                it("falls back to default config if custom config fails") {
                    let invalidPath = URL(fileURLWithPath: "/dev/null/invalid")

                    let reporter = BacktraceCrashReporter(
                        crashDirectory: invalidPath,
                        fileProtection: .complete
                    )
                    
                    expect { try reporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                }
            }
        }
    }
}
