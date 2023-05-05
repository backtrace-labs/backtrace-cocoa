import Foundation

struct BreadcrumbRecord {
    let size: Int
    let json: String
    
    init(size: Int, json: String) {
        self.size = size
        self.json = json
    }
}
