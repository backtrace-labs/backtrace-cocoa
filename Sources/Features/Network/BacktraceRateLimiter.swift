import Foundation

final class BacktraceRateLimiter {
    private var records: [TimeInterval]
    let reportsPerMin: Int
    private let cacheInterval = 60.0
    private let lock = NSLock()
    private let currentTime: () -> TimeInterval

    init(timestamps: [TimeInterval] = [],
         reportsPerMin: Int,
         currentTime: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.records = timestamps
        self.reportsPerMin = reportsPerMin
        self.currentTime = currentTime
    }

    var timestamps: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    var canSend: Bool {
        lock.lock()
        defer { lock.unlock() }

        if reportsPerMin == 0 { return true }
        guard reportsPerMin > 0 else { return false }
        pruneExpiredRecords(now: currentTime())
        return records.count < reportsPerMin
    }

    /// Atomically checks the current window and reserves capacity for one submission.
    /// A zero limit represents unlimited delivery and intentionally records no timestamps.
    /// Negative values are invalid and fail closed to preserve the historical behavior.
    func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if reportsPerMin == 0 { return true }
        guard reportsPerMin > 0 else { return false }

        let now = currentTime()
        pruneExpiredRecords(now: now)
        guard records.count < reportsPerMin else { return false }
        records.append(now)
        return true
    }

    private func pruneExpiredRecords(now: TimeInterval) {
        records.removeAll { now - $0 >= cacheInterval }
    }
}
