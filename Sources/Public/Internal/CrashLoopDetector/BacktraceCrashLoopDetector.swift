//
//  BacktraceCrashLoopDetector.swift
//  Backtrace
//

import Foundation

@objc internal class BacktraceCrashLoopDetector: NSObject {
    
    internal struct StartUpEvent: Codable {
        var uuid: String
        var eventTimestamp: Double
        var reportCreationTimestamp: Double
        
        func description() -> String {
            let string = """
                            New Crash Loop Event:
                            UUID: \(uuid)
                            Event Timestamp: \(eventTimestamp)
                            Report Creation Timestamp: \(reportCreationTimestamp)\n
                         """
            return string
        }
    }

    internal static let instance = BacktraceCrashLoopDetector()

    @objc private static let plistKey = "CrashLoopDetectorData"
    @objc internal static let consecutiveCrashesThreshold = 5
    @objc private(set) var consecutiveCrashesCount = 0

    @objc private var threshold = 0
    
    internal var startupEvents: [StartUpEvent] = []

    override private init() {
    }

    @objc internal func updateThreshold(_ threshold: Int) {
        self.threshold = threshold == 0 ? BacktraceCrashLoopDetector.consecutiveCrashesThreshold : threshold
    }
    
    @objc internal func detectCrashloop() -> Bool {

        CLDLogDebug("Starting Crash Loop Detection")
        
        loadEvents()
        addEvent()

        consecutiveCrashesCount = consecutiveEventsCount()

        let result = consecutiveCrashesCount >= BacktraceCrashLoopDetector.consecutiveCrashesThreshold
        CLDLogDebug("Finishing Crash Loop Detection: Is in the crash loop - \(result)")
        return result
    }

    @objc private func loadEvents() {
        
        // Cleanup old events - f.e. for multiple usages of detector
        startupEvents.removeAll()
        
        /*
         - Since detector's DB is relatively small, UserDefaults are a good option here,
         plus they allow to avoid a headache with reading/writing to/from the custom file.

         - But we should consider shared computers as well - comment from UserDefaults docs:
            With the exception of managed devices in educational institutions,
            a user’s defaults are stored locally on a single device,
            and persisted for backup and restore.
            To synchronize preferences and other data across a user’s connected devices,
            use NSUbiquitousKeyValueStore instead.
         */
        guard let data = UserDefaults.standard.object(forKey: BacktraceCrashLoopDetector.plistKey) as? Data
        else { return }

        guard let array = try? PropertyListDecoder().decode([StartUpEvent].self, from: data)
        else { return }

        startupEvents.append(contentsOf: array)
        CLDLogDebug("Events Loaded: \(startupEvents.count)")
    }

    @objc private func saveEvents() {
        let data = try? PropertyListEncoder().encode(startupEvents)
        UserDefaults.standard.set(data, forKey: BacktraceCrashLoopDetector.plistKey)
        CLDLogDebug("Events Saved: \(startupEvents.count)")
    }

    @objc private func addEvent() {
        
        let reportTime = reportFileCreationTime()

        let event = StartUpEvent(uuid: UUID().uuidString,
                                 eventTimestamp: Double(Date.timeIntervalSinceReferenceDate),
                                 reportCreationTimestamp: reportTime)
        
        CLDLogDebug(event.description())

        startupEvents.insert(event, at: 0)
        
        while startupEvents.count > BacktraceCrashLoopDetector.consecutiveCrashesThreshold && !startupEvents.isEmpty {
            startupEvents.removeFirst()
        }

        CLDLogDebug("Startup Event Added, Total Events => \(startupEvents.count)")

        saveEvents()
    }

    @objc internal func clearStartupEvents() {
        startupEvents.removeAll()
        saveEvents()
        CLDLogDebug("Startup Events Cleared: \(startupEvents.count)")
    }
    
    @objc internal func consecutiveEventsCount() -> Int {
        
        var count = 0
        var previousTime = 0.0
        for event in startupEvents {
            if event.reportCreationTimestamp == 0 || event.reportCreationTimestamp == previousTime {
                break
            }
            
            if previousTime == 0 || event.reportCreationTimestamp < previousTime {
                count += 1
            }

            previousTime = event.reportCreationTimestamp
        }
        CLDLogDebug("Consecutive Events Count: \(count)")
        return count
    }
    
    @objc internal func databaseDescription() -> String {
        var string = ""
        for event in startupEvents {
            string += event.description() + "\n"
        }
        return string.isEmpty ? "No events" : string
    }
}

// MARK: Deprecated methods
extension BacktraceCrashLoopDetector {

    @objc private func reportFilePath() -> String {
        
        /*  Crash Loop Detector considers all other Backtrace modules as potentially dangerous.
            Thats why it formats path to PLCrashReporter's report file itself,
            for not to use PLCrashReporter's APIs at all
         */
        
        let bundleIDBT = Bundle.main.bundleIdentifier ?? ""
        let appIDPath = bundleIDBT.replacingOccurrences(of: "/", with: "_")

        let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        let cacheDir = URL(fileURLWithPath: paths.isEmpty ? "" : paths[0])

        let bundleIDPLCR = "com.plausiblelabs.crashreporter.data"
        let crashReportDir = cacheDir.appendingPathComponent(bundleIDPLCR)
                                     .appendingPathComponent(appIDPath)

        let reportName = "live_report.plcrash"
        let reportFullPath = crashReportDir.appendingPathComponent(reportName)
                                           .absoluteString
                                           .replacingOccurrences(of: "file://", with: "")
        CLDLogDebug("reportFullPath: \(reportFullPath)")

        return reportFullPath
    }

    @objc private func reportFileCreationTime() -> Double {
        let attributes = try? FileManager.default.attributesOfItem(atPath: reportFilePath())
        let date = attributes?[.creationDate] as? Date
        CLDLogDebug("Report creation date: \(String(describing: date))")
        let timeInterval = date?.timeIntervalSinceReferenceDate ?? 0
        CLDLogDebug("Time Interval \(timeInterval)")
        return timeInterval
    }
    
    @available(*, deprecated, message: "Temporarily not needed")
    @objc internal func hasCrashReport() -> Bool {
        let exists = FileManager.default.fileExists(atPath: reportFilePath())
        return exists
    }

    @available(*, deprecated, message: "Temporarily not needed")
    @objc internal func deleteCrashReport() {
        let path = reportFilePath()
        let fileURL = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: fileURL)
        saveEvents()
    }
}


internal func CLDLogDebug(_ message: String = "") {

    /*  Routed logging here to add prefix for more convenient filtering of
        BTCLD logs in Xcode's outputs
     */
    let prefix = "BT CLD: "

    /*  Since Backtrace is not enabled during Crash Loop detection,
        BacktraceLogger is also not set up, so it doesn't log messages
        => using native 'print' here
     */
    print(prefix + message)
}
