import Foundation

struct Memory {
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
}
