import Foundation

extension ProcessInfo {
    static func boottime() throws -> time_t {
        var boottime: timeval = timeval()
        try System.systemControl(mib: [CTL_KERN, KERN_BOOTTIME], returnType: &boottime)
        return boottime.tv_sec
    }
}
