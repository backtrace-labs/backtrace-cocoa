import Foundation

protocol DebuggerChecking {
    static func isAttached() -> Bool
}

struct DebuggerChecker: DebuggerChecking {

    /// Check if the debugger is attached to the current process.
    /// - see more: https://stackoverflow.com/a/4746378/6651241
    ///
    /// - Returns: `true` if the debugger is attached, `false` otherwise
    static func isAttached() -> Bool {

        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        sysctl(&mib, u_int(mib.count), &kinfo, &size, nil, 0)

        return (kinfo.kp_proc.p_flag & P_TRACED) != 0
    }
}
