import Nimble
import Quick
#if SWIFT_PACKAGE
import Foundation
#endif
@testable import Backtrace

final class BacktraceRateLimiterTests: QuickSpec {
    // swiftlint:disable:next function_body_length
    override func spec() {
        describe("Rate limiter") {
            context("given empty sent list") {
                let rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
                it("allows to send new reports") {
                    expect { rateLimiter.canSend }.to(beTrue())
                }
            }

            context("given list containing not enough elements") {
                let rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
                _ = rateLimiter.acquire()
                _ = rateLimiter.acquire()
                it("allows to send new reports") {
                    expect { rateLimiter.canSend }.to(beTrue())
                }
            }

            context("given an unlimited configuration") {
                let rateLimiter = BacktraceRateLimiter(reportsPerMin: 0)

                it("allows every submission without retaining timestamps") {
                    for _ in 0..<1_000 {
                        expect(rateLimiter.acquire()).to(beTrue())
                    }

                    expect(rateLimiter.canSend).to(beTrue())
                    expect(rateLimiter.timestamps).to(beEmpty())
                }
            }

            context("given an invalid negative configuration") {
                let rateLimiter = BacktraceRateLimiter(reportsPerMin: -1)

                it("rejects submissions without retaining timestamps") {
                    expect(rateLimiter.canSend).to(beFalse())
                    expect(rateLimiter.acquire()).to(beFalse())
                    expect(rateLimiter.timestamps).to(beEmpty())
                }
            }

            context("given expired records") {
                var now = 1_000.0
                let rateLimiter = BacktraceRateLimiter(timestamps: [900, 950, 999],
                                                       reportsPerMin: 3,
                                                       currentTime: { now })

                it("prunes the expired window before reserving capacity") {
                    expect(rateLimiter.acquire()).to(beTrue())
                    expect(rateLimiter.timestamps).to(equal([950, 999, 1_000]))

                    now = 1_061
                    expect(rateLimiter.acquire()).to(beTrue())
                    expect(rateLimiter.timestamps).to(equal([1_061]))
                }
            }

            context("given a full rolling window") {
                var now = 1_030.0
                let rateLimiter = BacktraceRateLimiter(timestamps: [1_000],
                                                       reportsPerMin: 1,
                                                       currentTime: { now })

                it("reports when the next reservation becomes available") {
                    expect(rateLimiter.delayUntilNextAvailability()).to(equal(30))

                    now = 1_060
                    expect(rateLimiter.delayUntilNextAvailability()).to(equal(0))
                    expect(rateLimiter.acquire()).to(beTrue())
                }
            }

            it("reports immediate availability for an unlimited configuration") {
                let rateLimiter = BacktraceRateLimiter(reportsPerMin: 0)
                expect(rateLimiter.delayUntilNextAvailability()).to(equal(0))
            }

            it("does not schedule future availability for an invalid configuration") {
                let rateLimiter = BacktraceRateLimiter(reportsPerMin: -1)
                expect(rateLimiter.delayUntilNextAvailability()).to(beNil())
            }

            context("is used concurrently") {
                 let rateLimiter = BacktraceRateLimiter(reportsPerMin: 60)
                 it("atomically bounds reservations") {
                     let group = DispatchGroup()
                     for _ in 1...100 {
                         DispatchQueue.global().async(group: group) {
                             _ = rateLimiter.acquire()
                         }
                     }
                     group.wait()

                     expect { rateLimiter.timestamps.count }.to(equal(60))
                 }
             }
        }
    }
}
