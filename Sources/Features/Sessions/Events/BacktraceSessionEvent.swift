import Foundation

/// A single event in the session timeline, matching the TF wire protocol.
struct BacktraceSessionEvent: Codable {

    /// Seconds since session start (except network events which use ms since epoch).
    let ts: TimeInterval

    /// Event type enum value (matches TF `EventType` constants).
    let type: Int

    /// Event-specific payload. Keys and values vary by type.
    let data: [String: SessionEventValue]

    /// Only present on log events (value: `"-1"`).
    var id: String?
}

/// A type-erased value for session event data fields.
/// Supports String, Int, Double, Bool, and nested dictionaries.
enum SessionEventValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: SessionEventValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([String: SessionEventValue].self) { self = .dictionary(v); return }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported value type")
        )
    }
}

// MARK: - Event Type Constants (TF wire protocol)

enum SessionEventType {
    static let log = 1
    static let memoryInfo = 2
    static let input = 3
    static let battery = 7
    static let cpuInfo = 14
    static let meta = 16
    static let responsiveness = 20
    static let diskInfo = 21
    static let checkpoint = 25
    static let userInteraction = 26
    static let encryptedLog = 29
}

// MARK: - Meta Event Type Constants

enum SessionMetaType: Int, Codable {
    case offlineMode = 1
    case sessionCapped = 2
    case logFileMissing = 3
    case appInBackground = 4
    case appInForeground = 5
    case appInactive = 6
    case appNotResponding = 7
    case notDefaultCrashHandler = 8
    case wifiConnection = 12
    case mobileConnection = 13
    case noConnection = 14
    case sessionStoppedWhileInBackground = 17
    case newSessionResumedFromBackground = 18
    case sessionStoppedProgrammatically = 19
    case sessionAttribute = 20
    case disableVideoRecording = 22
    case sessionFileAttachment = 23
    case caughtException = 24
    case deviceScreenshotTaken = 25
    case methodUse = 27
    case aesKey = 28
    case badEncryptionKey = 29
    case sessionRecordingPaused = 34
    case sessionRecordingResumed = 35
}
