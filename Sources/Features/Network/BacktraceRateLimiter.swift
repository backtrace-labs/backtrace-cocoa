import Foundation

struct BacktraceRateLimiter {
    private(set) var timestamps: [TimeInterval] = []
    let reportsPerMin: Int
    private let cacheInterval = 60.0

    var canSend: Bool {
        let currentTimestamp = Date().timeIntervalSince1970
        let sentCount = timestamps.filter { currentTimestamp - $0 < cacheInterval }.count
        return sentCount < reportsPerMin
    }

    mutating func addRecord() {
        timestamps.append(Date().timeIntervalSince1970)
    }
}
