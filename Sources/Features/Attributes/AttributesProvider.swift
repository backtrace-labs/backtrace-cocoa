import Foundation

final class AttributesProvider {
    // attributes can be modified on runtime
    var userAttributes: Attributes = [:]
    var defaultAttributes: Attributes {
         return DefaultAttributes.current()
    }
}

extension AttributesProvider: SignalContext {
    var attributes: Attributes {
        return userAttributes + defaultAttributes
    }
}

extension AttributesProvider: CustomStringConvertible {
    var description: String {
        return attributes.compactMap { "\($0.key): \($0.value)"}.joined(separator: "\n")
    }
}
