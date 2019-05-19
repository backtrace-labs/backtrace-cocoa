import Foundation

struct Memory {
    let active: UInt
    let free: UInt
    let inactive: UInt
    let resident: UInt
    let residentPeak: UInt
    let virtual: UInt
    let used: UInt
    let total: UInt
    
    init() throws {
        let vmStatistics64 = try Memory.vmStatistics64()
        let taskVmInfo = try Processor.taskVmInfo()
        let pageSize = UInt(getpagesize())
        let taskInfo = try Processor.machTaskBasicInfo()
        self.active = UInt(vmStatistics64.active_count) * pageSize
        self.free = UInt(vmStatistics64.free_count) * pageSize
        self.inactive = UInt(vmStatistics64.inactive_count) * pageSize
        self.resident = UInt(taskVmInfo.resident_size)
        self.residentPeak = UInt(taskVmInfo.resident_size_peak)
        self.virtual = UInt(taskVmInfo.virtual_size)
        let wire = UInt(vmStatistics64.wire_count) * pageSize
        self.used = self.active + self.inactive + wire
        self.total = self.used + self.free
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
        let total: UInt
        let used: UInt
        let free: UInt
        
        init() throws {
            var usage = xsw_usage()
            try System.systemControl(mib: [CTL_VM, VM_SWAPUSAGE], returnType: &usage)
            
            self.total = UInt(usage.xsu_total)
            self.free = UInt(usage.xsu_avail)
            self.used = UInt(usage.xsu_used)
        }
    }
}
