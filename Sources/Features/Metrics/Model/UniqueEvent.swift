import Foundation

final class UniqueEvent: Event {

    // Backtrace API requires unique event name to be a JSON array
    internal(set) public var name = [String]()

    init(name: String) {
        self.name.append(name)
        super.init()
    }

    private enum CodingKeys: String, CodingKey {
        case name = "unique"
    }

    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
    }
}
