import Foundation

class SummedEventsPayload: Payload<SummedEvent> {
    
    private enum CodingKeys : String, CodingKey {
        case metadata, events = "summed_events", appName = "application", appVersion = "appversion"
    }
}
