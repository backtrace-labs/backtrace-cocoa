import Foundation

final class BacktraceRateLimiter: @unchecked Sendable {
    private(set) var timestamps: [TimeInterval] = []
    let reportsPerMin: Int
    private let cacheInterval = 60.0
    private let lock = NSLock()

    init(timestamps: [TimeInterval] = [], reportsPerMin: Int) {
        self.timestamps = timestamps
        self.reportsPerMin = reportsPerMin
    }

    var canSend: Bool {
        let currentTimestamp = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        let sentCount = timestamps.filter { currentTimestamp - $0 < cacheInterval }.count
        return sentCount < reportsPerMin
    }

    func addRecord() {
        lock.lock()
        defer { lock.unlock() }
        timestamps.append(Date().timeIntervalSince1970)
    }
}
