import Foundation

final class SummedEvent: Event {
    
    internal(set) public var name: String

    private enum CodingKeys : String, CodingKey {
        case timestamp, attributes, name = "metric_group"
    }
    
    init(name: String) {
        self.name = name
        super.init()
    }
}
