import XCTest
import Nimble
import Quick

@testable import Backtrace

final class BacktraceBreadcrumbTests: QuickSpec {

    let breadcrumbLogFileName = "bt-breadcrumbs-0"
    let defaultMaxLogSize = 64000
    func breadcrumbLogPath(_ create: Bool) throws -> String {
        var fileURL = try FileManager.default.url(for: .documentDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: create)
        fileURL.appendPathComponent(breadcrumbLogFileName)
        return fileURL.path
    }

    func readBreadcrumbText() -> String? {
        do {
            let path = try breadcrumbLogPath(true)
            let fileURL = URL(fileURLWithPath: path)
            let content = try String(contentsOf: fileURL, encoding: .ascii)
            return content
        } catch {
            return nil
        }
    }

    override func spec() {
        describe("Breadcrumbs") {

            var breadcrumb: BacktraceBreadcrumb?

            beforeEach {
                do {
                    try FileManager.default.removeItem(atPath: self.breadcrumbLogPath(false))
                } catch {
                }
                breadcrumb = BacktraceBreadcrumb()
            }
            afterEach {
                breadcrumb = nil
            }
            context("are not enabled") {
                it("fails to add breadcrumb") {
                    expect { breadcrumb?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadcrumb?.getCurrentBreadcrumbId }.to(beNil())
                    let result = breadcrumb?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beFalse())
                    let breadcrumbText = self.readBreadcrumbText()
                    expect { breadcrumbText }.to(beNil())
                }
            }
            context("are enabled") {
                it("Able to add breadcrumbs and they are all added to the breadcrumb file without overflowing") {
                    breadcrumb?.enableBreadcrumbs()
                    expect { breadcrumb?.isBreadcrumbsEnabled }.to(beTrue())
                    expect { breadcrumb?.getCurrentBreadcrumbId }.toNot(beNil())

                    //  100 iterations won't overflow the file yet
                    for index in 0...50 {
                        expect { breadcrumb?.addBreadcrumb("this is Breadcrumb number \(index)") }.to(beTrue())
                    }

                    let breadcrumbText = self.readBreadcrumbText()
                    for index in 0...50 {
                        expect { breadcrumbText }.to(contain("this is Breadcrumb number \(index)"))
                    }
                }
                it("Again disable breadcrumb") {
                    breadcrumb?.disableBreadcrumbs()
                    expect { breadcrumb?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadcrumb?.getCurrentBreadcrumbId }.to(beNil())
                }
            }
            context("rollover tests") {
                it("rolls over after enough breadcrumbs are added to get the maximum file size") {
                    // 8196 is the minimum, setting 1 would just revert to that minimum
                    breadcrumb?.enableBreadcrumbs(maxLogSize: 1)
                    var size = 0
                    var writeIndex = 0

                    // intentionally write over 4096 bytes, causing the file to overflow and rotate
                    while size < 4096 + 128 {
                        writeIndex += 1
                        let breadcrumbText = "this is Breadcrumb number \(writeIndex)"
                        expect { breadcrumb?.addBreadcrumb(breadcrumbText) }.to(beTrue())
                        size += breadcrumbText.utf8.count
                    }

                    let breadcrumbText = self.readBreadcrumbText()!

                    // should have been rolled away
                    expect { breadcrumbText }.toNot(contain("this is Breadcrumb number 0"))

                    // Not very scientific, but 119 is apparently when the file wraps
                    var matches = 0
                    let wrapIndex = 119
                    for readIndex in wrapIndex...writeIndex {
                        let match = breadcrumbText.contains("this is Breadcrumb number \(readIndex)")
                        if match {
                            matches += 1
                        }
                    }

                    // Why the - 1?
                    // Because one line is liable to get mangled by the wrapping - half will
                    // be at the bottom and half at the top of the circular file.
                    // Currently, we accept we lose this Breadcrumb in the UI - it will still be in the file
                    // for manual inspection.
                    let expectedNumberOfMatches = writeIndex - wrapIndex - 1
                    expect(matches).to(beGreaterThanOrEqualTo(expectedNumberOfMatches),
                                       description: "Not enough (\(expectedNumberOfMatches))" +
                                       "breadcrumb matches found in breadcrumbs file: \n\(breadcrumbText)")
                }
            }
        }
    }
}
