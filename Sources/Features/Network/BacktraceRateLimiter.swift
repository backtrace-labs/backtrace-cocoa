import Foundation

struct BacktraceRateLimiter {
    internal var timestamps: [TimeInterval] = []
    let reportsPerMin: Int
    private let cacheInterval = 60.0
    private let lock = NSLock()

    var canSend: Bool {
        let currentTimestamp = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        let sentCount = timestamps.filter { currentTimestamp - $0 < cacheInterval }.count
        return sentCount < reportsPerMin
    }

    mutating func addRecord() {
        let currentTimestamp = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        // evict old entries
        timestamps.removeAll(where: { currentTimestamp - $0 >= cacheInterval })
        timestamps.append(currentTimestamp)
    }
}
