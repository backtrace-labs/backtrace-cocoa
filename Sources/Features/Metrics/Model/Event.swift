import Foundation

protocol Event: Encodable {

    var timestamp: Int64 { get set }
    var attributes: DecodableAttributes { get set }
}

extension Event {
    func initialTimestamp() -> Int64 {
        return Date().currentTimeSeconds()
    }

    func initialAttributes() -> DecodableAttributes {
        let attributesProvider = AttributesProvider()
        let localAttributes = attributesProvider.allAttributes
        let localAttributesConverted: [String: String] = localAttributes.compactMapValues { "\($0)" }

        return localAttributesConverted
    }
}
