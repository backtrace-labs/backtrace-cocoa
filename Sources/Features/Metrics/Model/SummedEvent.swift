import Foundation

final class SummedEvent: Event {
    
    internal(set) public var name: String
    
    init(name: String) {
        self.name = name
        super.init()
    }
    
    private enum CodingKeys: String, CodingKey {
        case name = "metric_group"
    }
    
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
    }
}
