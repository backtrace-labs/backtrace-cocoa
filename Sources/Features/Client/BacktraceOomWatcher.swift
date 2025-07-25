import Foundation
import CrashReporter
import MachO

/// Handles low‑memory warnings and, on the next launch, decides if the previous session ended in an OOM crash.
///
/// **Thread‑safety:**
/// Every public entry‑point hops onto a dedicated serial `queue` : `DispatchQueue`
/// Callers may invoke the watcher from *any* context without risk of races.
/// Internal helpers prefixed with `_` expect to already be on that queue.
final class BacktraceOomWatcher {

    /// Milliseconds after handling a low‑memory warning during which further warnings are ignored.
    /// default is 60 seconds
    var quietTimeInMillis: Int = 60_000

    // MARK: Private & internal
    
    private static let oomFileName = "BacktraceOomState.plist"
    internal static var oomFileURL: URL? = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(oomFileName)
    }()

    // MARK: Dependencies
    
    private let crashReporter: CrashReporting
    private(set) var attributesProvider: AttributesProvider
    private let backtraceApi: BacktraceApi
    private let repository: PersistentRepository<BacktraceReport>
    private let oomMode: BacktraceOomMode

    // MARK: Concurrency

    /// Serial queue for all heavy or file‑system work to keep launch fast and avoid races.
    internal let queue: DispatchQueue

    // MARK: Application State (persisted across launches)

    internal struct ApplicationInfo: Codable {
        var state: ApplicationState = .active
        var debugger: Bool          = DebuggerChecker.isAttached()
        var appVersion: String      = BacktraceOomWatcher.appVersion()
        var osVersion: String       = ProcessInfo.processInfo.operatingSystemVersionString
        var memoryWarningReceived   = false
        var memoryWarningTimestamp: Int?
    }

    internal enum ApplicationState: String, Codable { case active, inactive, background }

    /// In‑memory copy of the current session’s state (serialised to disk on mutation).
    internal var state = ApplicationInfo()

    // MARK: Static helpers to store attributes/attachments between sessions

    internal static var reportAttributes: Attributes? {
        get { try? AttributesStorage.retrieve(fileName: "oom_report") }
        set {
            do {
                if let newValue = newValue {
                    try AttributesStorage.store(newValue, fileName: "oom_report")
                } else {
                    try AttributesStorage.remove(fileName: "oom_report")
                }
            } catch { BacktraceLogger.error(error) }
        }
    }

    internal static var reportAttachments: Attachments? {
        get { try? AttachmentsStorage.retrieve(fileName: "oom_report") }
        set {
            do {
                if let newValue = newValue {
                    try AttachmentsStorage.store(newValue, fileName: "oom_report")
                } else {
                    try AttachmentsStorage.remove(fileName: "oom_report")
                }
            } catch { BacktraceLogger.error(error) }
        }
    }

    // MARK: Init / Deinit

    init(repository: PersistentRepository<BacktraceReport>,
         crashReporter: CrashReporting,
         attributes: AttributesProvider,
         backtraceApi: BacktraceApi,
         oomMode: BacktraceOomMode,
         qos: DispatchQoS = .utility) {

        self.repository       = repository
        self.crashReporter    = crashReporter
        self.attributesProvider = attributes
        self.backtraceApi     = backtraceApi
        self.oomMode          = oomMode
        self.queue            = DispatchQueue(label: "com.backtrace.oom", qos: qos)

        // If the default cache location was not resolved, store next to the DB.
        if Self.oomFileURL == nil {
            Self.oomFileURL = repository.url.deletingLastPathComponent()
                                .appendingPathComponent(Self.oomFileName)
        }
    }

    deinit { Self.clean() }

    // MARK: Public API (non-blocking)

    func start() {
        guard oomMode != .none else { return }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self._sendPendingOomReports()
            self._saveState()
        }
    }

    func appChangedState(_ newState: ApplicationState) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.state.state = newState
            self._saveState()
        }
    }

    /// A normal termination wipes the OOM marker
    func handleTermination() {
        queue.async {
            Self.clean()
        }
    }

    func handleLowMemoryWarning() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let now = Date().millisecondsSince1970
            // ignore if within quiet window
            if let last = self.state.memoryWarningTimestamp,
               now - last < self.quietTimeInMillis {
                return
            }
            
            self.state.memoryWarningTimestamp = now
            self.state.memoryWarningReceived  = true
            
            // attributes
            var attrs = self.attributesProvider.allAttributes
            attrs["error.message"] = "Out of memory detected."
            attrs["error.type"] = "Low Memory"
            attrs["memory.warning.timestamp"] = now
            attrs["state"] = self.state.state.rawValue
            
            if let footprint = Self.currentMemoryFootprint() {
                attrs["memory.footprint.bytes"] = footprint
            }
            
            Self.reportAttributes = attrs
            Self.reportAttachments = self.attributesProvider.allAttachments
            
            self._saveState()
        }
    }

    // MARK: Private – only run on `queue`

    internal func _sendPendingOomReports() {
        defer { Self.clean() }

        guard let url = Self.oomFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let previousState = _loadPreviousState() else { return }

        guard _shouldReportOom(previousState) else { return }

        _reportOom()
    }

    private func _shouldReportOom(_ prev: ApplicationInfo) -> Bool {
        
        guard prev.memoryWarningReceived else { return false }
        guard !prev.debugger else { return false }
        guard prev.osVersion == ProcessInfo.processInfo.operatingSystemVersionString else { return false }
        guard prev.appVersion == Self.appVersion() else { return false }
        return true
    }

    private func _reportOom() {
        // oomMode to use [.light, .full]
        // never called if oomMode == .none.
        switch oomMode {
        case .light:
            if _sendLightweightOom() { return }
            BacktraceLogger.warning("Lightweight OOM capture failed – retrying with full report.")
            // fall back on .full if .light fails
            fallthrough
        case .full:
            _sendFullOom()
            // edge case (watcher not created in `.none`)
        case .none:
            return
        }
    }

    // MARK: Report styles

    /// .light path: current thread only, no symbolication – returns `true` on success.
    private func _sendLightweightOom() -> Bool {
        // PLCrashReporterSymbolicationStrategyNone = [] due to how Swift interoperates with objc
        // because PLCrashReporterSymbolicationStrategy is defined as an NS_OPTIONS.
        let cfg = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: [])
        let lightReporter = PLCrashReporter(configuration: cfg)
        let thread = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, thread) }

        guard let data = try? lightReporter?.generateLiveReport(withThread: thread, exception: nil),
              let report = try? BacktraceReport(report: data,
                                                attributes: Self.reportAttributes ?? [:],
                                                attachmentPaths: Self.reportAttachments?.map(\.path) ?? []) else {
            return false
        }
        do {
            _ = try backtraceApi.send(report)
        } catch {
            BacktraceLogger.error(error)
            try? repository.save(report)
        }
        return true
    }

    /// Full path: legacy behaviour (all threads, symbolicated).
    private func _sendFullOom() {
        guard let live = try? crashReporter.generateLiveReport(exception: nil,
                                                               attributes: [:],
                                                               attachmentPaths: [])
        else {
            BacktraceLogger.warning("Unable to construct full OOM crash report.")
            return
        }
        
        guard let report = try? BacktraceReport(report: live.reportData,
                                                attributes: Self.reportAttributes ?? [:],
                                                attachmentPaths: Self.reportAttachments?.map(\.path) ?? []) else {
            return
        }
        do {
            _ = try backtraceApi.send(report)
        } catch {
            BacktraceLogger.error(error)
            try? repository.save(report)
        }
    }

    // MARK: State persistence

    internal func _loadPreviousState() -> ApplicationInfo? {
        guard let url = Self.oomFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(ApplicationInfo.self, from: data)
    }

    private func _saveState() {
        guard let url = Self.oomFileURL,
              let data = try? PropertyListEncoder().encode(state) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data)
        }
    }

    // MARK: Helpers

    /// Removes persisted OOM flag + cached attrs/attachments.
    internal static func clean() {
        if let url = Self.oomFileURL { try? FileManager.default.removeItem(at: url) }
        reportAttributes  = nil
        reportAttachments = nil
    }

    internal static func appVersion() -> String {
        let dict = Bundle.main.infoDictionary
        // appVersion is also known as the marketing version as shown on the app store
        // buildVersion is usually the build number
        let app  = dict?["CFBundleShortVersionString"] as? String ?? ""
        let build = dict?["CFBundleVersion"]           as? String ?? ""
        return app + "-" + build
    }

    /// Returns the resident size of the current process in bytes or `nil` if unavailable.
    private static func currentMemoryFootprint() -> UInt64? {
        var info  = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info)) / 4
        let kerr  = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
}
