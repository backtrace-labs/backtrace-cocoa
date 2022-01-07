import Foundation

struct UniqueEventsPayload: Payload {

    typealias Event = UniqueEvent

    var applicationName: String
    var applicationVersion: String
    var metadata: EventsMetadata
    var events: [UniqueEvent]

    init(events: [UniqueEvent]) {
        self.applicationName = UniqueEventsPayload.getApplicationName()
        self.applicationVersion = UniqueEventsPayload.getApplicationVersion()
        self.metadata = EventsMetadata()
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case events = "unique_events", applicationName = "application", applicationVersion = "appversion", metadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(applicationName, forKey: .applicationName)
        try container.encode(applicationVersion, forKey: .applicationVersion)
        try container.encode(metadata, forKey: .metadata)
    }
}
