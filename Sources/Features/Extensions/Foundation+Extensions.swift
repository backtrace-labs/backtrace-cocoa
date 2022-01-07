import Foundation

extension Dictionary {

    static func + (lhs: Dictionary, rhs: Dictionary) -> Dictionary {
        return lhs.merging(rhs, uniquingKeysWith: {_, new in new})
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
}
