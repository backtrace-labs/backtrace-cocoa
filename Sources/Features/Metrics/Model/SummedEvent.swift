import Foundation

struct SummedEvent: Event {

    var timestamp: Int64
    var attributes: DecodableAttributes

    var name = String()

    init(name: String) {
        self.timestamp = SummedEvent.initialTimestamp()
        self.attributes = SummedEvent.initialAttributes()
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name = "metric_group", timestamp, attributes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(attributes, forKey: .attributes)
    }
}
