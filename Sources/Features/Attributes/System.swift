import Foundation

extension ProcessInfo {
    func boottime() throws -> time_t {
        var boottime = timeval()
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var size = MemoryLayout<timeval>.stride
        
        let result = sysctl(&mib, 2, &boottime, &size, nil, 0)
        guard result == KERN_SUCCESS else {
            throw KernError.code(result)
        }
        
        return boottime.tv_sec
    }
}
