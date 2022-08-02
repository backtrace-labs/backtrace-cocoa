// swiftlint:disable function_body_length cyclomatic_complexity

import XCTest
import Nimble
import Quick

@testable import Backtrace

/** Module test, not unit test. Tests the entire breadcrumbs module */
final class BacktraceBreadcrumbTests: QuickSpec {

    let breadcrumbLogFileName = "bt-breadcrumbs-0"

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
        describe("BacktraceBreadcrumbs") {

            var breadcrumbs: BacktraceBreadcrumbs?

            beforeEach {
                do {
                    try FileManager.default.removeItem(atPath: self.breadcrumbLogPath(false))
                } catch {
                    print("\(error.localizedDescription)")
                }
                breadcrumbs = BacktraceBreadcrumbs()
            }
            afterEach {
                breadcrumbs?.disableBreadcrumbs()
                breadcrumbs = nil
            }
            context("breadcrumbs are not enabled") {
                it("fails to add breadcrumb") {
                    breadcrumbs?.disableBreadcrumbs()
                    expect { breadcrumbs?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadcrumbs?.getCurrentBreadcrumbId }.to(beNil())
                    expect { breadcrumbs?.addBreadcrumb("Breadcrumb submit test") }.to(beFalse())
                    expect { self.readBreadcrumbText() }.to(beNil())
                }
            }
            context("breadcrumbs are enabled") {
                it("fails to add breadcrumb for lower breadcrumb level") {
                    breadcrumbs?.enableBreadcrumbs(BacktraceBreadcrumbSettings(breadcrumbLevel: BacktraceBreadcrumbLevel.error))
                    expect { breadcrumbs?.allowBreadcrumbsToAdd(.info) }.to(beFalse())
                    expect { breadcrumbs?.addBreadcrumb("Info Breadcrumb", level: .info) }.to(beFalse())
                    expect { self.readBreadcrumbText() }.toNot(contain("Info Breadcrumb"))
                }
                it("able to add breadcrumb for higher breadcrumb level") {
                    breadcrumbs?.enableBreadcrumbs(BacktraceBreadcrumbSettings(breadcrumbLevel: BacktraceBreadcrumbLevel.error))
                    expect { breadcrumbs?.allowBreadcrumbsToAdd(.fatal) }.to(beTrue())
                    expect { breadcrumbs?.addBreadcrumb("Fatal Breadcrumb", level: .fatal) }.to(beTrue())
                    let breadcrumbText = self.readBreadcrumbText()
                    expect { breadcrumbText }.toNot(beNil())
                    expect { breadcrumbText }.to(contain("Fatal Breadcrumb"))
                    expect { breadcrumbText }.to(contain("\"level\":\"fatal\""))
                }
                it("Able to add breadcrumbs and they are all added to the breadcrumb file without overflowing") {
                    breadcrumbs?.enableBreadcrumbs()
                    expect { breadcrumbs?.isBreadcrumbsEnabled }.to(beTrue())
                    expect { BreadcrumbsInfo.currentBreadcrumbsId }.toNot(beNil())
                    expect { breadcrumbs?.getCurrentBreadcrumbId }.toNot(beNil())
                    expect { BreadcrumbsInfo.currentBreadcrumbsId }.to(equal(breadcrumbs?.getCurrentBreadcrumbId))

                    //  50 iterations won't overflow the file yet
                    for index in 0...50 {
                        expect { breadcrumbs?.addBreadcrumb("this is Breadcrumb number \(index)") }.to(beTrue())
                    }

                    let breadcrumbText = self.readBreadcrumbText()
                    for index in 0...50 {
                        expect { breadcrumbText }.to(contain("this is Breadcrumb number \(index)"))
                    }
                }
                it("Able to add breadcrumbs with all possible options (level, type, attributes)") {
                    breadcrumbs?.enableBreadcrumbs()

                    expect { breadcrumbs?.addBreadcrumb("this is a Breadcrumb ",
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
                    breadcrumbs?.enableBreadcrumbs()

                    var text = "this is a Breadcrumb"
                    while text.utf8.count < 4096 {
                        text += text
                    }

                    expect { breadcrumbs?.addBreadcrumb(text)}.to(beFalse())

                    let breadcrumbText = self.readBreadcrumbText()
                    expect { breadcrumbText }.notTo(contain("this is a Breadcrumb"))
                }
                it("Again disable breadcrumb") {
                    breadcrumbs?.disableBreadcrumbs()
                    expect { breadcrumbs?.isBreadcrumbsEnabled }.to(beFalse())
                    expect { breadcrumbs?.getCurrentBreadcrumbId }.to(beNil())
                }
            }
            context("rollover and async tests") {
                it("rolls over after enough breadcrumbs are added to get to the maximum file size") {
                    let settings = BacktraceBreadcrumbSettings()
                    settings.maxQueueFileSizeBytes = 32 * 1024
                    breadcrumbs?.enableBreadcrumbs(settings)

                    let group = DispatchGroup()

                    // intentionally write over allowed bytes, causing the file to overflow and rotate
                    var writeIndex = 0
                    while writeIndex < 1000 {
                        let text = "this is Breadcrumb number \(writeIndex)"
                        // submit a task to the queue for background execution
                        DispatchQueue.global().async(group: group, execute: {
                            expect { breadcrumbs?.addBreadcrumb(text) }.to(beTrue())
                        })
                        writeIndex += 1
                    }

                    group.wait()

                    let breadcrumbText = self.readBreadcrumbText()!

                    // Not very scientific, but this is apparently when the file wraps
                    let wrapIndex = 742
                    for readIndex in 0...wrapIndex {
                        // should have been rolled away
                        expect { breadcrumbText }.toNot(contain("\"this is Breadcrumb number \(readIndex)\""))
                    }

                    var matches = 0
                    if writeIndex < wrapIndex {
                        fail("\(writeIndex) is smaller than \(wrapIndex)")
                    } else {
                        for readIndex in wrapIndex...writeIndex {
                            let match = breadcrumbText.contains("\"this is Breadcrumb number \(readIndex)\"")
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
                                           description: "Not enough (\(matches) out of \(expectedNumberOfMatches)) " +
                                           "breadcrumb matches found in breadcrumbs file: \n\(breadcrumbText)")

                        let attr = try FileManager.default.attributesOfItem(atPath: self.breadcrumbLogPath(false))
                        let fileSize = attr[FileAttributeKey.size] as? Int
                        let requestedSize = settings.maxQueueFileSizeBytes
                        expect { fileSize }.to(beLessThanOrEqualTo(requestedSize))
                        expect { fileSize }.to(beGreaterThanOrEqualTo(requestedSize - 1000))
                    }
                }
            }
        }
        describe("BacktraceNotificationObserver") {
            beforeEach {
                do {
                    try FileManager.default.removeItem(atPath: self.breadcrumbLogPath(false))
                } catch {
                    print("\(error.localizedDescription)")
                }
            }
            context("when notification observed") {
                let breadcrumbs = BacktraceBreadcrumbs()
                breadcrumbs.enableBreadcrumbs()
                let mockOrientationNotificationObserver = BacktraceOrientationNotificationObserverMock()
                let mockBatteryNotificationObserver = BacktraceBatteryNotificationObserverMock()
                let mockMemoryNotificationObserver = BacktraceMemoryNotificationObserverMock()
                _ = BacktraceNotificationObserver(breadcrumbs: breadcrumbs, handlerDelegates: [
                    mockOrientationNotificationObserver,
                    mockBatteryNotificationObserver,
                    mockMemoryNotificationObserver])
                mockOrientationNotificationObserver.addOrientationBreadcrumb("Landscape")
                mockBatteryNotificationObserver.addBatteryBreadcrumb(10)
                mockMemoryNotificationObserver.addMemoryBreadcrumb("Normal level memory pressure event")
                let breadcrumbText = self.readBreadcrumbText()

                it("notification breadcremb added") {
#if os(iOS)
                    expect { breadcrumbText }.to(contain("\"orientation\":\"Landscape\""))
                    expect { breadcrumbText }.to(contain("Orientation changed"))
#endif
                    expect { breadcrumbText }.to(contain("full battery level : 10%"))
                    expect { breadcrumbText }.to(contain("Normal level memory pressure event"))
                }
            }
        }
    }
}
