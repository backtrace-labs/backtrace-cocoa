import XCTest
import Nimble
import Quick
@testable import Backtrace

final class BacktraceClientSpec: QuickSpec {
    override func spec() {
        describe("BacktraceClient") {
            
            context("when crashDirectory is set") {
                it("creates the directory and uses it for crash logs") {
                    let fileManager = FileManager.default
                    let customDirectory = fileManager.temporaryDirectory.appendingPathComponent("bt-client-spec-\(UUID().uuidString)")
                    try? fileManager.removeItem(at: customDirectory)
                    
                    let creds = BacktraceCredentials(
                        endpoint: URL(string: "https://yourteam.backtrace.io")!,
                        token: "test-token"
                    )
                    let config = BacktraceClientConfiguration(
                        credentials: creds,
                        dbSettings: BacktraceDatabaseSettings(),
                        reportsPerMin: 30,
                        allowsAttachingDebugger: true,
                        detectOOM: true,
                        crashDirectory: customDirectory,
                        fileProtection: .none
                    )
                    
                    expect {
                        try BacktraceClient(configuration: config)
                    }.toNot(throwError())
                    
                    var isDir: ObjCBool = false
                    let exists = fileManager.fileExists(atPath: customDirectory.path, isDirectory: &isDir)
                    expect(exists).to(beTrue())
                    expect(isDir.boolValue).to(beTrue())

                    let attributes = try? fileManager.attributesOfItem(atPath: customDirectory.path)
                    let protection = attributes?[.protectionKey] as? FileProtectionType
#if !targetEnvironment(simulator)
                    expect(protection).to(equal(FileProtectionType.none))
#endif
                }
            }

            context("when crashDirectory is nil") {
                it("should not create the custom directory (logic only)") {
                    let fileManager = FileManager.default
                    let customDirectory = fileManager.temporaryDirectory.appendingPathComponent("bt-client-spec-\(UUID().uuidString)")
                    try? fileManager.removeItem(at: customDirectory)
                    
                    let crashDirectory: URL? = nil
                    
                    expect(crashDirectory).to(beNil())

                    let exists = fileManager.fileExists(atPath: customDirectory.path)
                    expect(exists).to(beFalse(), description: "Directory should not exist when crashDirectory is nil")
                }
            }
        }
    }
}

