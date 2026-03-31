import Foundation

/// Thread-safe ring buffer for session events.
///
/// When the buffer reaches capacity, a flush is triggered. Events are never dropped;
/// they are flushed to the network or persisted offline before new events overwrite them.
final class BacktraceSessionEventBuffer {

    private var buffer: [BacktraceSessionEvent] = []
    private let maxSize: Int
    private let lock = NSLock()

    /// Callback invoked when the buffer reaches capacity and should be flushed.
    var onBufferFull: (() -> Void)?

    init(maxSize: Int) {
        self.maxSize = maxSize
        buffer.reserveCapacity(maxSize)
    }

    /// Append an event to the buffer. Triggers `onBufferFull` if capacity is reached.
    func append(_ event: BacktraceSessionEvent) {
        lock.lock()
        buffer.append(event)
        let shouldFlush = buffer.count >= maxSize
        lock.unlock()

        if shouldFlush {
            onBufferFull?()
        }
    }

    /// Take a snapshot of all buffered events and clear the buffer.
    ///
    /// - Returns: Array of events that were in the buffer.
    func flush() -> [BacktraceSessionEvent] {
        lock.lock()
        let snapshot = buffer
        buffer.removeAll(keepingCapacity: true)
        lock.unlock()
        return snapshot
    }

    /// Current number of events in the buffer.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// Whether the buffer has reached its capacity.
    var isFull: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count >= maxSize
    }

    /// Whether the buffer is empty.
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.isEmpty
    }
}
