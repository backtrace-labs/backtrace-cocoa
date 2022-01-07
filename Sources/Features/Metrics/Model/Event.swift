import Foundation

protocol Event: Encodable {

    var timestamp: Int64 { get set }
    var attributes: DecodableAttributes { get set }
}

extension Event {
    static func initialTimestamp(_ date: Date = Date()) -> Int64 {
        return date.currentTimeSeconds()
    }

    static func initialAttributes(_ attributesProvider: AttributesProvider = AttributesProvider()) -> DecodableAttributes {
        let localAttributes = attributesProvider.allAttributes
        let localAttributesConverted: [String: String] = localAttributes.compactMapValues { "\($0)" }

        return localAttributesConverted
    }
}
