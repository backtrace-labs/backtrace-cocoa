import Foundation

extension Dictionary {
    
    static func + (lhs: Dictionary, rhs: Dictionary) -> Dictionary {
        return lhs.merging(rhs, uniquingKeysWith: {_, new in new})
    }
}
