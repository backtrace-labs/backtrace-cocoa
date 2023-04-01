import Nimble
import Quick
@testable import Backtrace

final class BacktraceRateLimiterTests: QuickSpec {
    override func spec() {
//        describe("Rate limiter") {
//            context("given empty sent list") {
//                let rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
//                it("allows to send new reports") {
//                    expect { rateLimiter.canSend }.to(beTrue())
//                }
//            }
//
//            context("given list containing not enough elements") {
//                var rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
//                rateLimiter.addRecord()
//                rateLimiter.addRecord()
//                it("allows to send new reports") {
//                    expect { rateLimiter.canSend }.to(beTrue())
//                }
//            }
//
//            context("is used concurrently") {
//                 var rateLimiter = BacktraceRateLimiter(reportsPerMin: 60)
//                 it("doesn't crash") {
//                     let group = DispatchGroup()
//                     for _ in 1...100 {
//                         DispatchQueue.global().async(group: group) {
//                             rateLimiter.addRecord()
//                         }
//                     }
//                     group.wait()
//
//                     expect { rateLimiter.timestamps.count }.to(equal(100))
//                 }
//             }
//        }
    }
}
