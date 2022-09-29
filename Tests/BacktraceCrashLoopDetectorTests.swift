import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceCrashLoopDetectorTests: QuickSpec {

    override func spec() {
        describe("Crash Loop Detector") {

            let crashLoopDetector = BacktraceCrashLoopDetector()
            let eventsCount = BacktraceCrashLoopDetector.consecutiveCrashesThreshold
            let timeIntervalStep = 200
            var isCrashLoop = false
            
            context("No Crash Loop Case") {
                
                let expectedResult = false
                
                for index in 0 ..< eventsCount {
                    let timestamp = Date.timeIntervalSinceReferenceDate - Double(timeIntervalStep * (eventsCount - index))
                    let mockEvent = BacktraceCrashLoopDetector.StartUpEvent(timestamp: timestamp, isSuccessful: .random())
                    crashLoopDetector.startupEvents.append(mockEvent)
                }
                crashLoopDetector.saveEvents()
                isCrashLoop = crashLoopDetector.detectCrashloop()
                
                it("checks if no crash loop detected") {
                    expect { isCrashLoop == expectedResult }.to(beTrue())
                }
            }

            context("Crash Loop Case") {
                
                let expectedResult = true
                
                for index in 0 ..< eventsCount {
                    let timestamp = Date.timeIntervalSinceReferenceDate - Double(timeIntervalStep * (eventsCount - index))
                    let mockEvent = BacktraceCrashLoopDetector.StartUpEvent(timestamp: timestamp, isSuccessful: false)
                    crashLoopDetector.startupEvents.append(mockEvent)
                }
                crashLoopDetector.saveEvents()
                let isCrashLoop = crashLoopDetector.detectCrashloop()
                
                it("checks if crash loop detected") {
                    expect { isCrashLoop == expectedResult }.to(beTrue())
                }
            }
        }
    }
}
