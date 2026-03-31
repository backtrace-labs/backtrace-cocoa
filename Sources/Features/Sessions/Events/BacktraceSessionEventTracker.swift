import Foundation

/// Manages event buffering, periodic flushing, gzip compression, and submission.
///
/// Events are collected into a ring buffer and periodically flushed to the server
/// as gzip-compressed JSON. On flush failure, events are persisted to offline storage.
final class BacktraceSessionEventTracker {

    /// Updated when the server responds with a session token.
    var sessionToken: String?

    private let buffer: BacktraceSessionEventBuffer
    private let sessionId: String
    private let startTime: Date
    private let api: BacktraceSessionApi
    private let storage: BacktraceSessionStorage
    private let queue = DispatchQueue(label: "io.backtrace.sessions.events", qos: .utility)

    private var flushTimer: DispatchSourceTimer?

    init(bufferSize: Int,
         flushInterval: TimeInterval,
         sessionId: String,
         startTime: Date,
         api: BacktraceSessionApi,
         storage: BacktraceSessionStorage) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.api = api
        self.storage = storage
        self.buffer = BacktraceSessionEventBuffer(maxSize: bufferSize)

        self.buffer.onBufferFull = { [weak self] in
            self?.flush()
        }

        startFlushTimer(interval: flushInterval)
    }

    deinit {
        flushTimer?.cancel()
    }

    // MARK: - Event Creation

    /// Add a meta event to the buffer.
    func addMetaEvent(metaType: SessionMetaType, data: [String: String]? = nil) {
        var eventData: [String: SessionEventValue] = [
            "type": .int(metaType.rawValue)
        ]
        if let extra = data {
            for (key, value) in extra {
                eventData[key] = .string(value)
            }
        }

        let event = BacktraceSessionEvent(
            ts: secondsSinceStart(),
            type: SessionEventType.meta,
            data: eventData
        )
        buffer.append(event)
    }

    /// Add a checkpoint/user event.
    func addCheckpointEvent(name: String) {
        let event = BacktraceSessionEvent(
            ts: secondsSinceStart(),
            type: SessionEventType.checkpoint,
            data: ["name": .string(name)]
        )
        buffer.append(event)
    }

    /// Add a log event.
    func addLogEvent(tag: String, text: String, level: BacktraceSessionLogLevel) {
        var event = BacktraceSessionEvent(
            ts: secondsSinceStart(),
            type: SessionEventType.log,
            data: [
                "tag": .string(tag),
                "text": .string(text),
                "level": .string(level.wireValue)
            ]
        )
        event.id = "-1"
        buffer.append(event)
    }

    /// Add a CPU metrics event.
    func addCPUEvent(userTime: Double, systemTime: Double, threads: Double) {
        let event = BacktraceSessionEvent(
            ts: secondsSinceStart(),
            type: SessionEventType.cpuInfo,
            data: [
                "utime": .double(userTime),
                "stime": .double(systemTime),
                "threads": .double(threads)
            ]
        )
        buffer.append(event)
    }

    /// Add a memory metrics event.
    func addMemoryEvent(free: Int, active: Int, shared: Int, privateBytes: Int) {
        let event = BacktraceSessionEvent(
            ts: secondsSinceStart(),
            type: SessionEventType.memoryInfo,
            data: [
                "free": .int(free),
                "active": .int(active),
                "shared": .int(shared),
                "private": .int(privateBytes)
            ]
        )
        buffer.append(event)
    }

    /// Add a battery metrics event.
    func addBatteryEvent(level: Double, status: Int, plugged: Int) {
        let event = BacktraceSessionEvent(
            ts: secondsSinceStart(),
            type: SessionEventType.battery,
            data: [
                "level": .double(level),
                "scale": .int(100),
                "status": .int(status),
                "plugged": .int(plugged)
            ]
        )
        buffer.append(event)
    }

    /// Collect system metrics based on settings.
    func collectSystemMetrics(settings: BacktraceSessionSettings) {
        if settings.collectCPU {
            let cpuInfo = BacktraceSessionMetricsCollector.collectCPU()
            addCPUEvent(userTime: cpuInfo.userTime, systemTime: cpuInfo.systemTime, threads: cpuInfo.threads)
        }
        if settings.collectMemory {
            let memInfo = BacktraceSessionMetricsCollector.collectMemory()
            addMemoryEvent(free: memInfo.free, active: memInfo.active, shared: memInfo.shared, privateBytes: memInfo.privateBytes)
        }
        #if os(iOS)
        if settings.collectBattery {
            let batteryInfo = BacktraceSessionMetricsCollector.collectBattery()
            addBatteryEvent(level: batteryInfo.level, status: batteryInfo.status, plugged: batteryInfo.plugged)
        }
        #endif
    }

    // MARK: - Flushing

    /// Flush all buffered events to the server.
    func flush() {
        queue.async { [weak self] in
            self?.performFlush()
        }
    }

    private func performFlush() {
        let events = buffer.flush()
        guard !events.isEmpty else { return }

        do {
            let payload = ["events": events]
            let jsonData = try JSONEncoder().encode(payload)
            let compressed = try BacktraceGzipCompressor.compress(jsonData)

            let storageCopy = self.storage
            api.sendEvents(
                compressed,
                sessionToken: sessionToken,
                completion: { (result: Swift.Result<Void, Swift.Error>) in
                    switch result {
                    case .success:
                        break
                    case .failure:
                        try? storageCopy.save(type: .events, data: compressed)
                    }
                }
            )
        } catch {
            BacktraceLogger.error("Failed to encode/compress events: \(error)")
        }
    }

    // MARK: - Private

    private func startFlushTimer(interval: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.performFlush()
        }
        timer.resume()
        flushTimer = timer
    }

    private func secondsSinceStart() -> TimeInterval {
        return Date().timeIntervalSince(startTime)
    }
}
