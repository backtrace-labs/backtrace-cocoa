import Foundation

protocol AttributesSource {
    var immutable: [String: Any?] { get }
    var mutable: [String: Any?] { get }
}

extension AttributesSource {
    var immutable: [String: Any?] { return [:] }
    var mutable: [String: Any?] { return [:] }
}

final class AttributesProvider {
    
    // attributes can be modified on runtime
    var attributes: Attributes = [:]
    private let attributesSources: [AttributesSource]
    private let faultInfo: FaultInfo
    
    lazy var immutable: Attributes = {
        return attributesSources.map(\.immutable).merging()
    }()
    
    init() {
        faultInfo = FaultInfo()
        attributesSources = [ProcessorInfo(),
                             Device(),
                             ScreenInfo(),
                             LocaleInfo(),
                             NetworkInfo(),
                             LibInfo(),
                             LocationInfo(),
                             faultInfo]
    }
}

extension AttributesProvider: SignalContext {
    func set(faultMessage: String?) {
        self.faultInfo.faultMessage = faultMessage
    }
    
    var allAttributes: Attributes {
        return attributes + defaultAttributes
    }
    
    var defaultAttributes: Attributes {
        return immutable + attributesSources.map(\.mutable).merging()
    }
}

extension AttributesProvider: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        return allAttributes.compactMap { "\($0.key): \($0.value)"}.joined(separator: "\n")
    }
    
    var debugDescription: String {
        return description
    }
}

extension Array where Element == [String: Any?] {
    func merging() -> [String: Any] {
        let keyValuePairs = reduce([:], +).compactMap({ (key: String, value: Any?) -> (key: String, value: Any)? in
            guard let value = value else {
                return nil
            }
            return (key, value)
        })
        return Dictionary(keyValuePairs) { (lhs, _) in lhs }
    }
}
