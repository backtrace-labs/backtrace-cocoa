import Foundation

class UniqueEventsPayload: Payload<UniqueEvent> {

    private enum CodingKeys: String, CodingKey {
        case events = "unique_events"
    }

    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
    }
}
