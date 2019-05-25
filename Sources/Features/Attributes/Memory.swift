import Foundation
import Darwin

struct Memory {
    struct Virtual {
        let active: UInt64
        let free: UInt64
        let inactive: UInt64
        let wired: UInt64
        let compressed: UInt64
        
        let resident: UInt64
        let residentPeak: UInt64
        let virtual: UInt64
        let used: UInt64
        let total: UInt64
        
        let swapins: UInt64
        let swapouts: UInt64
        
        init() throws {
            let vmStatistics64 = try Memory.vmStatistics64()
            let taskVmInfo = try Processor.taskVmInfo()
            let pageSize = UInt64(getpagesize())
            
            self.active = UInt64(vmStatistics64.active_count) * pageSize
            self.free = UInt64(vmStatistics64.free_count) * pageSize
            self.inactive = UInt64(vmStatistics64.inactive_count) * pageSize
            self.virtual = UInt64(taskVmInfo.virtual_size)
            self.wired = UInt64(vmStatistics64.wire_count) * pageSize
            self.compressed = UInt64(vmStatistics64.compressor_page_count) * pageSize
            self.swapins = vmStatistics64.swapins
            self.swapouts = vmStatistics64.swapouts
            self.used = self.active + self.inactive + self.wired
            self.total = self.used + self.free
            
            self.resident = UInt64(taskVmInfo.resident_size)
            self.residentPeak = UInt64(taskVmInfo.resident_size_peak)
        }
    }
    
    static func vmStatistics64() throws -> vm_statistics64 {
        var vmStatInfo = vm_statistics64()
        var size: mach_msg_type_number_t =
            UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kernReturn = withUnsafeMutablePointer(to: &vmStatInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), host_flavor_t(HOST_VM_INFO64), $0, &size)
            }
        }
        guard kernReturn == KERN_SUCCESS else {
            throw KernError.code(kernReturn)
        }
        return vmStatInfo
    }
    
    struct Swap {
        let total: UInt64
        let used: UInt64
        let free: UInt64
        
        init() throws {
            var usage = xsw_usage()
            try System.systemControl(mib: [CTL_VM, VM_SWAPUSAGE], returnType: &usage)
            self.total = UInt64(usage.xsu_total)
            self.free = UInt64(usage.xsu_avail)
            self.used = UInt64(usage.xsu_used)
        }
    }
}
