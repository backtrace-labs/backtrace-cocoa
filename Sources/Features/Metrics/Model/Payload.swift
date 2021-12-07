import Foundation

class EventsMetadata: Encodable {
    var droppedEvents = 0
    
    private enum CodingKeys : String, CodingKey {
        case droppedEvents = "dropped_events"
    }
}

class Payload<T: Event>: Encodable {
    
    var metadata = EventsMetadata()
    var events: [T]
    
    init(events: [T]) {
        self.events = events
    }
}

extension Payload {
    static var applicationName: String { return Backtrace.applicationName ?? "" }
    static var applicationVersion: String { return Backtrace.applicationVersion ?? "" }
}
