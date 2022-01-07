import Foundation

struct UniqueEvent: Event {

    var timestamp: Int64
    var attributes: DecodableAttributes

    // Backtrace API requires unique event name to be a JSON array
    var name = [String]()

    init(name: String) {
        self.timestamp = UniqueEvent.initialTimestamp()
        self.attributes = UniqueEvent.initialAttributes()
        self.name.append(name)
    }

    private enum CodingKeys: String, CodingKey {
        case name = "unique", timestamp, attributes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(attributes, forKey: .attributes)
    }
}
