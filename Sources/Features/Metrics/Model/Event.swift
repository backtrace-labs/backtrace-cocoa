import Foundation

enum EventType {
    case Unique, Summed
}

class Event: Encodable {
    var timestamp: Int64
    var attributes = DecodableAttributes()
    
    init() {
        let localAttributes: [String: String] = attributes.compactMapValues { "\($0)" }
        self.attributes.merge(localAttributes) { (_, new) in new }

        self.timestamp = Date().currentTimeSeconds()
    }
}
