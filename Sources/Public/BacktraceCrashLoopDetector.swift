//
//  BacktraceCrashLoopDetector.swift
//  Backtrace
//

import Foundation
import Backtrace_PLCrashReporter

@objc public class BacktraceCrashLoopDetector: NSObject {
        
    enum SafetyMode {
        case normal
        case safe
    }

    internal struct StartUpEvent: Codable {
        var timestamp: Double
        var isSuccessful: Bool
    }
    
    @objc private static let plistKey = "CrashLoopDB"
    @objc internal static let eventsForCrashLoopCount = 5

    internal var startupEvents: [StartUpEvent] = []
    
    @objc private func loadEvents() {
        
        // Cleanup old events - f.e, for multiple usages of detector
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
        print("Events Loaded: \(startupEvents.count)")
    }
    
    @objc internal func saveEvents() {
        let data = try? PropertyListEncoder().encode(startupEvents)
        UserDefaults.standard.set(data, forKey: BacktraceCrashLoopDetector.plistKey)
        print("Events Saved: \(startupEvents.count)")
    }
    
    @objc private func addCurrentEvent() {
        var event = StartUpEvent(timestamp: Double(Date.timeIntervalSinceReferenceDate), isSuccessful: true)

        let plReporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())

        if plReporter?.hasPendingCrashReport() ?? false {
            event.isSuccessful = false
        }
//        event.isSuccessful = false
        print("New Event: {timestamp:\(event.timestamp)--successful:\(event.isSuccessful)}")

        startupEvents.append(event)
        
        if startupEvents.count > BacktraceCrashLoopDetector.eventsForCrashLoopCount {
            startupEvents.remove(at: 0)
        }

        print("Event Added: \(startupEvents.count)")
    }

    @objc private func badEventsCount() -> Int {
        
        var badEventsCount = 0
        for event in startupEvents {
            badEventsCount += (event.isSuccessful ? 0 : 1)
        }
        
        print("Bad Events Count: \(badEventsCount)")
        return badEventsCount
    }
    
    @objc func detectCrashloop() -> Bool {

        print("Starting Crash Loop Detection")
        
        loadEvents()

        addCurrentEvent()
        
        let count = badEventsCount()
        saveEvents()

        // true -> crash loop detected -> set safe mode
        // false -> crash loop NOT detected -> set normal mode
        let result = count >= BacktraceCrashLoopDetector.eventsForCrashLoopCount
        print("Finishing Crash Loop Detection: \(result)")
        return result
    }
}
