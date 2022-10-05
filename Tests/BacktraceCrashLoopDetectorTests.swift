import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceCrashLoopDetectorTests: QuickSpec {

    override func spec() {
        describe("Crash Loop Detector") {
            
            context("No Crash Loop Case") {

                let crashLoopDetector = BacktraceCrashLoopDetector()
                let eventsCount = BacktraceCrashLoopDetector.consecutiveCrashesThreshold
                let timeIntervalStep = 200

                for index in 0 ..< eventsCount {
                    let timestamp = Date.timeIntervalSinceReferenceDate - Double(timeIntervalStep * (eventsCount - index))
                    let mockEvent = BacktraceCrashLoopDetector.StartUpEvent(timestamp: timestamp, isSuccessful: .random())
                    crashLoopDetector.startupEvents.append(mockEvent)
                }
                crashLoopDetector.saveEvents()
                
                let isCrashLoop = crashLoopDetector.detectCrashloop()
                it("checks if no crash loop detected") {
                    expect { isCrashLoop }.to(beFalse())
                }
            }

            context("Crash Loop Case") {
                                
                let crashLoopDetector = BacktraceCrashLoopDetector()
                let eventsCount = BacktraceCrashLoopDetector.consecutiveCrashesThreshold
                let timeIntervalStep = 200

                for index in 0 ..< eventsCount {
                    let timestamp = Date.timeIntervalSinceReferenceDate - Double(timeIntervalStep * (eventsCount - index))
                    let mockEvent = BacktraceCrashLoopDetector.StartUpEvent(timestamp: timestamp, isSuccessful: false)
                    crashLoopDetector.startupEvents.append(mockEvent)
                }
                crashLoopDetector.saveEvents()
                
                let isCrashLoop = crashLoopDetector.detectCrashloop()
                it("checks if crash loop detected") {
                    expect { isCrashLoop }.to(beTrue())
                }
            }
        }
    }
}
