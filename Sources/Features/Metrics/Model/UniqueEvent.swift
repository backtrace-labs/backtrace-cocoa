import Foundation

final class UniqueEvent: Event {
    
    // Backtrace API requires unique event name to be a JSON array
    internal(set) public var name = [String]()
    
    private enum CodingKeys : String, CodingKey {
        case timestamp, attributes, name = "unique"
    }
    
    init(name: String) {
        self.name.append(name)
        super.init()
    }
}
