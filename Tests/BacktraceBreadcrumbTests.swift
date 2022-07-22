// swiftlint:disable function_body_length

import XCTest
import Nimble
import Quick

@testable import Backtrace

/** Module test, not unit test. Tests the entire breadcrumbs module */
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
        describe("BreadcrumbsLogManager") {
            var manager: BacktraceBreadcrumbsLogManager?
            beforeEach {
                do {
                    try FileManager.default.removeItem(atPath: self.breadcrumbLogPath(false))
                } catch {
                    print("\(error.localizedDescription)")
                }
                do {
                    let setting = BacktraceBreadcrumbSettings(maxQueueFileSizeBytes: 8192)
                    try manager = BacktraceBreadcrumbsLogManager(breadcrumbSettings: setting)
                } catch {
                    fail("\(error.localizedDescription)")
                }
            }
            context("when constructed") {
                it("Clear clears the file") {
                    expect { manager?.addBreadcrumb("this is a Breadcrumb",
                                                    attributes: nil,
                                                    type: BacktraceBreadcrumbType.system,
                                                    level: BacktraceBreadcrumbLevel.debug)}.to(beTrue())

                    expect { self.readBreadcrumbText() }.to(contain("this is a Breadcrumb"))

                    expect { manager?.clear() }.to(beTrue())

                    expect { self.readBreadcrumbText() }.toNot(contain("this is a Breadcrumb"))

                    expect { manager?.addBreadcrumb("this is a Breadcrumb",
                                                    attributes: nil,
                                                    type: BacktraceBreadcrumbType.system,
                                                    level: BacktraceBreadcrumbLevel.debug)}.to(beTrue())

                    expect { self.readBreadcrumbText() }.to(contain("this is a Breadcrumb"))
                }
            }
        }
        describe("BacktraceClientConfiguration") {

            var breadcrumb: BacktraceBreadcrumbs?

            beforeEach {
                do {
                    try FileManager.default.removeItem(atPath: self.breadcrumbLogPath(false))
                } catch {
                    print("\(error.localizedDescription)")
                }
                breadcrumb = BacktraceBreadcrumbs()
            }
            afterEach {
                breadcrumb = nil
            }
            context("breadcrumbs are not enabled") {
                it("fails to add breadcrumb") {
                    breadcrumb?.disableBreadcrumbs()
                    expect { breadcrumb?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadcrumb?.getCurrentBreadcrumbId }.to(beNil())
                    let result = breadcrumb?.addBreadcrumb("Breadcrumb submit test")
                    expect { result }.to(beFalse())
                    let breadcrumbText = self.readBreadcrumbText()
                    expect { breadcrumbText }.toNot(contain("Breadcrumb submit test"))
                }
            }
            context("breadcrumbs are enabled") {
                it("Able to add breadcrumbs and they are all added to the breadcrumb file without overflowing") {
                    breadcrumb?.enableBreadcrumbs()
                    expect { breadcrumb?.isBreadcrumbsEnabled }.to(beTrue())
                    expect { breadcrumb?.getCurrentBreadcrumbId }.toNot(beNil())

                    //  50 iterations won't overflow the file yet
                    for index in 0...50 {
                        expect { breadcrumb?.addBreadcrumb("this is Breadcrumb number \(index)") }.to(beTrue())
                    }

                    let breadcrumbText = self.readBreadcrumbText()
                    for index in 0...50 {
                        expect { breadcrumbText }.to(contain("this is Breadcrumb number \(index)"))
                    }
                }
                it("Able to add breadcrumbs with all possible options (level, type, attributes)") {
                    breadcrumb?.enableBreadcrumbs()

                    expect { breadcrumb?.addBreadcrumb("this is a Breadcrumb ",
                                                       attributes: ["a": "b", "c": "1"],
                                                       type: .navigation,
                                                       level: .fatal) }.to(beTrue())

                    let breadcrumbText = self.readBreadcrumbText()
                    expect { breadcrumbText }.to(contain("this is a Breadcrumb"))
                    expect { breadcrumbText }.to(contain("\"type\":\"navigation\""))
                    expect { breadcrumbText }.to(contain("\"level\":\"fatal\""))
                    expect { breadcrumbText }.to(contain("\"attributes\":{"))
                    expect { breadcrumbText }.to(contain("\"a\":\"b\""))
                    expect { breadcrumbText }.to(contain("\"c\":\"1\""))
                }
                it("Too long breadcrumb (>4kB) gets rejected") {
                    breadcrumb?.enableBreadcrumbs()

                    var text = "this is a Breadcrumb"
                    while text.utf8.count < 4096 {
                        text += text
                    }

                    expect { breadcrumb?.addBreadcrumb(text)}.to(beFalse())

                    let breadcrumbText = self.readBreadcrumbText()
                    // text will contain a bunch of null bytes from the library, but should contain the breadcrumb itself
                    expect { breadcrumbText }.notTo(contain("this is a Breadcrumb"))
                }
                it("Again disable breadcrumb") {
                    breadcrumb?.disableBreadcrumbs()
                    expect { breadcrumb?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadcrumb?.getCurrentBreadcrumbId }.to(beNil())
                }
                it("processReportBreadcrumbs") {
                    breadcrumb?.enableBreadcrumbs()

                    let crashReporter = BacktraceCrashReporter()
                    var report = try crashReporter.generateLiveReport(attributes: [:])
                    breadcrumb?.processReportBreadcrumbs(&report)

                    expect { report.attachmentPaths.first }.to(contain("bt-breadcrumbs-0"))
                    expect { report.attributes.first?.key }.to(contain("breadcrumbs.lastId"))
                }
            }
            context("rollover tests") {
                it("rolls over after enough breadcrumbs are added to get to the maximum file size") {
                    // 8196 is the minimum, setting 1 would just revert to that minimum
                    let setting = BacktraceBreadcrumbSettings(maxQueueFileSizeBytes: 1)
                    breadcrumb?.enableBreadcrumbs(setting)
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

                    // Not very scientific, but 119 is apparently when we reach 4k and the file wraps
                    let wrapIndex = 119
                    var matches = 0
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
