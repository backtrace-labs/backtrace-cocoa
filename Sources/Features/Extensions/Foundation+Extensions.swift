import Foundation
@preconcurrency import Darwin

/// Wraps `mach_task_self_` to silence the strict-concurrency warning about
/// the C global variable.  The underlying value is a per-process constant.
@inline(__always)
func currentTaskPort() -> mach_port_t {
    mach_task_self_
}

extension Dictionary {

    static func + (lhs: Dictionary, rhs: Dictionary) -> Dictionary {
        return lhs.merging(rhs, uniquingKeysWith: {_, new in new})
    }
    
    static func += (left: inout Dictionary, right: Dictionary) {
        for (key, value) in right {
            left[key] = value
        }
    }
}

// From: https://stackoverflow.com/a/57886995
extension Date {
    func currentTimeSeconds() -> Int64 {
        return Int64(self.timeIntervalSince1970)
    }
}

// From: https://stackoverflow.com/a/47066697
extension Bundle {
    var displayName: String? {
            return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}

// From: https://stackoverflow.com/a/28893525
extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}
