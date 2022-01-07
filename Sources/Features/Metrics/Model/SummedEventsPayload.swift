import Foundation

struct SummedEventsPayload: Payload {

    typealias Event = SummedEvent

    var applicationName: String
    var applicationVersion: String
    var metadata: EventsMetadata
    var events: [SummedEvent]

    init(events: [SummedEvent]) {
        self.applicationName = SummedEventsPayload.getApplicationName()
        self.applicationVersion = SummedEventsPayload.getApplicationVersion()
        self.metadata = EventsMetadata()
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case events = "summed_events", applicationName = "application", applicationVersion = "appversion", metadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(applicationName, forKey: .applicationName)
        try container.encode(applicationVersion, forKey: .applicationVersion)
        try container.encode(metadata, forKey: .metadata)
    }
}
