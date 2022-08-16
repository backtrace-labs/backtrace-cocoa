import Nimble
import Quick
@testable import Backtrace

final class BacktraceRateLimiterTests: QuickSpec {
    override func spec() {
        describe("Rate limiter") {
            context("given empty sent list") {
                let rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
                it("allows to send new reports") {
                    expect { rateLimiter.canSend }.to(beTrue())
                }
            }

            context("given list containing not enough elements") {
                var rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)
                rateLimiter.addRecord()
                rateLimiter.addRecord()
                it("allows to send new reports") {
                    expect { rateLimiter.canSend }.to(beTrue())
                }
            }

            context("given list containing enough elements to hit rate limit") {
                var rateLimiter = BacktraceRateLimiter(reportsPerMin: 3)

                rateLimiter.addRecord()
                rateLimiter.addRecord()
                it("doesn't allow to send more than 3 reports") {
                    expect { rateLimiter.canSend }.to(beTrue())
                    rateLimiter.addRecord()
                    expect { rateLimiter.canSend }.to(beFalse())
                }
            }

            context("given outdated entries in the list") {
                var rateLimiter = BacktraceRateLimiter(reportsPerMin: 60)
                rateLimiter.timestamps.append(Date().timeIntervalSince1970 - 61)
                rateLimiter.timestamps.append(Date().timeIntervalSince1970 - 600)
                rateLimiter.timestamps.append(Date().timeIntervalSince1970 - 6000)

                it("clears the oudated records upon append") {
                    expect { rateLimiter.timestamps.count }.to(equal(3))

                    rateLimiter.addRecord()

                    expect { rateLimiter.timestamps.count }.to(equal(1))
                }
            }

            context("is used concurrently") {
                var rateLimiter = BacktraceRateLimiter(reportsPerMin: 60)
                it("doesn't crash") {
                    let group = DispatchGroup()
                    for _ in 1...100 {
                        DispatchQueue.global().async(group: group) {
                            rateLimiter.addRecord()
                        }
                    }
                    group.wait()

                    expect { rateLimiter.timestamps.count }.to(equal(100))
                }
            }
        }
    }
}
