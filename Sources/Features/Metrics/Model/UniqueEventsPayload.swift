import Foundation

class UniqueEventsPayload: Payload<UniqueEvent> {
    
    private enum CodingKeys : String, CodingKey {
        case metadata, events = "unique_events", appName = "application", appVersion = "appversion"
    }
}
