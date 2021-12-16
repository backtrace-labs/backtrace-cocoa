import Foundation

class Event: Encodable {
    var timestamp: Int64
    var attributes = DecodableAttributes()
    
    init() {
        let attributesProvider = AttributesProvider()
        let localAttributes = attributesProvider.allAttributes
        let localAttributesConverted: [String: String] = localAttributes.compactMapValues { "\($0)" }
        
        self.attributes.merge(localAttributesConverted) { (_, new) in new }

        self.timestamp = Date().currentTimeSeconds()
    }
    
    private enum CodingKeys: String, CodingKey {
        case timestamp, attributes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(attributes, forKey: .attributes)
    }
}
