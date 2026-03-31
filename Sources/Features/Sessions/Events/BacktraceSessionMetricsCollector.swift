import Foundation
import Darwin
#if os(iOS)
import UIKit
#endif

/// Collects system metrics (CPU, memory, battery) for session events.
///
/// Reuses patterns from `DefaultAttributes.swift` (`ProcessorInfo`) but packages
/// results in the TF wire protocol format.
enum BacktraceSessionMetricsCollector {

    struct CPUInfo {
        let userTime: Double
        let systemTime: Double
        let threads: Double
    }

    struct MemoryInfo {
        let free: Int
        let active: Int
        let shared: Int       // Total physical memory in bytes
        let privateBytes: Int // Process resident memory in bytes
    }

    struct BatteryInfo {
        let level: Double  // 0–100
        let status: Int    // 1=unknown, 2=charging, 4=unplugged, 5=full
        let plugged: Int   // 0=no, 1=yes
    }

    // MARK: - CPU

    static func collectCPU() -> CPUInfo {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else {
            return CPUInfo(userTime: 0, systemTime: 0, threads: 0)
        }

        var totalUser: Double = 0
        var totalSystem: Double = 0

        for i in 0..<Int(threadCount) {
            var info = thread_basic_info_data_t()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)

            let kr = withUnsafeMutablePointer(to: &info) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { ptr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), ptr, &infoCount)
                }
            }

            if kr == KERN_SUCCESS {
                let userSec = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
                let sysSec = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
                totalUser += userSec
                totalSystem += sysSec
            }
        }

        // Deallocate thread list
        let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(threadCount))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        return CPUInfo(
            userTime: totalUser,
            systemTime: totalSystem,
            threads: Double(threadCount)
        )
    }

    // MARK: - Memory

    static func collectMemory() -> MemoryInfo {
        // Process memory
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &taskInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        let privateBytes: Int
        if kr == KERN_SUCCESS {
            privateBytes = Int(taskInfo.phys_footprint)
        } else {
            privateBytes = 0
        }

        // System memory
        var vmStats = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()

        let vmResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &vmCount)
            }
        }

        let pageSize = vm_kernel_page_size
        let freePages: Int
        let activePages: Int

        if vmResult == KERN_SUCCESS {
            freePages = Int(vmStats.free_count)
            activePages = Int(vmStats.active_count)
        } else {
            freePages = 0
            activePages = 0
        }

        return MemoryInfo(
            free: freePages * Int(pageSize),
            active: activePages * Int(pageSize),
            shared: Int(ProcessInfo.processInfo.physicalMemory),
            privateBytes: privateBytes
        )
    }

    // MARK: - Battery

    #if os(iOS)
    static func collectBattery() -> BatteryInfo {
        let device = UIDevice.current
        let wasEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true

        let level = Double(device.batteryLevel) * 100.0

        let status: Int
        let plugged: Int
        switch device.batteryState {
        case .unknown:
            status = 1; plugged = 0
        case .charging:
            status = 2; plugged = 1
        case .unplugged:
            status = 4; plugged = 0
        case .full:
            status = 5; plugged = 1
        @unknown default:
            status = 1; plugged = 0
        }

        if !wasEnabled {
            device.isBatteryMonitoringEnabled = false
        }

        return BatteryInfo(level: level, status: status, plugged: plugged)
    }
    #endif
}
