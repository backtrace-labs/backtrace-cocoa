import Foundation

struct EventsMetadata: Encodable {

    var droppedEvents = 0

    private enum CodingKeys: String, CodingKey {
        case droppedEvents = "dropped_events"
    }
}

protocol Payload: Encodable {

    associatedtype Event
    var applicationName: String { get }
    var applicationVersion: String { get }

    var metadata: EventsMetadata { get set }
    var events: [Event] { get set }

    init(events: [Event])
}

extension Payload {

    static func getApplicationName() -> String {
        return Backtrace.applicationName ?? ""
    }

    static func getApplicationVersion() -> String {
        return Backtrace.applicationVersion ?? ""
    }
}
