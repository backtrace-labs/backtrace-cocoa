import Foundation
import Testing
@testable import Backtrace

@Suite struct BacktraceRateLimiterTests {

    @Test func emptyListAllowsSendingNewReports() {
        let rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
        #expect(rateLimiter.canSend == true)
    }

    @Test func notEnoughElementsAllowsSendingNewReports() {
        let rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
        rateLimiter.addRecord()
        rateLimiter.addRecord()
        #expect(rateLimiter.canSend == true)
    }

    @Test func concurrentUsageDoesNotCrash() {
        let rateLimiter = BacktraceRateLimiter(reportsPerMin: 60)
        let group = DispatchGroup()
        for _ in 1...100 {
            DispatchQueue.global().async(group: group) {
                rateLimiter.addRecord()
            }
        }
        group.wait()

        #expect(rateLimiter.timestamps.count == 100)
    }
}
