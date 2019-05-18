import Foundation

struct System {
    static func systemControl<T>(mib: [Int32], returnType: inout T) throws {
        var mibInout: [Int32] = mib
        var size = MemoryLayout<T>.stride
        
        let result = sysctl(&mibInout, u_int(mibInout.count), &returnType, &size, nil, 0)
        guard result == KERN_SUCCESS else {
            throw KernError.code(result)
        }
    }
    
    static func boottime() throws -> time_t {
        var boottime: timeval = timeval()
        try systemControl(mib: [CTL_KERN, KERN_BOOTTIME], returnType: &boottime)
        return boottime.tv_sec
    }
    
    static func startTime() throws -> time_t {
        var kinfo: kinfo_proc = kinfo_proc()
        try systemControl(mib: [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()], returnType: &kinfo)
        return kinfo.kp_proc.p_starttime.tv_sec
    }
}
