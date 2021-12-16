import Foundation

class EventsMetadata: Encodable {
    var droppedEvents = 0

    private enum CodingKeys: String, CodingKey {
        case droppedEvents = "dropped_events"
    }
}

class Payload<T: Event>: Encodable {
    var applicationName = Backtrace.applicationName ?? ""
    var applicationVersion = Backtrace.applicationVersion ?? ""

    var metadata = EventsMetadata()
    var events: [T]

    init(events: [T]) {
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case metadata, applicationName = "application", applicationVersion = "appversion"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(applicationName, forKey: .applicationName)
        try container.encode(applicationVersion, forKey: .applicationVersion)
        try container.encode(metadata, forKey: .metadata)
    }
}

extension Payload {

}
