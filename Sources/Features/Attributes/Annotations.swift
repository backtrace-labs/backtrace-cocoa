import Foundation

struct Annotations {
    let environmentVariables: [String: String]
    let dependencies: [String: String]

    init() {
        environmentVariables = ProcessInfo.processInfo.environment

        let items = Bundle.allFrameworks.compactMap(FrameworkInfo.init)
            .map({($0.name, $0.version)})
        dependencies = Dictionary(items, uniquingKeysWith: { _, new in new })
    }
}

struct FrameworkInfo {
    let name: String
    let version: String
    let identifier: String

    init?(_ bundle: Bundle) {
        guard let name = bundle.infoDictionary?[kCFBundleNameKey as String] as? String,
            let version = bundle.infoDictionary?[kCFBundleVersionKey as String] as? String,
            let identifier = bundle.infoDictionary?[kCFBundleIdentifierKey as String] as? String else {
                return nil
        }
        self.name = name
        self.version = version
        self.identifier = identifier
    }
}
