import Foundation

struct BacktraceRateLimiter {
    private(set) var timestamps: [TimeInterval] = []
    let reportsPerMin: Int
    private let cacheInterval = 60.0
    private let lock = NSLock()

    var canSend: Bool {
        let currentTimestamp = Date().timeIntervalSince1970
        lock.lock()
        let sentCount = timestamps.filter { currentTimestamp - $0 < cacheInterval }.count
        lock.unlock()
        return sentCount < reportsPerMin
    }

    mutating func addRecord() {
        lock.lock()
        timestamps.append(Date().timeIntervalSince1970)
        lock.unlock()
    }
}
