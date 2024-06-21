import Foundation

protocol AttributesSource {
    var immutable: [String: Any?] { get }
    var mutable: [String: Any?] { get }
    var attachments: Attachments { get }
}

extension AttributesSource {
    var immutable: [String: Any?] { return [:] }
    var mutable: [String: Any?] { return [:] }
    var attachments: Attachments { return [] }
}

final class AttributesProvider {

    // attributes can be modified on runtime
    var attributes: Attributes = [:]
    var attachments: Attachments = []
    private let attributesSources: [AttributesSource]
    private let faultInfo: FaultInfo

    lazy var immutable: Attributes = {
        return attributesSources.map(\.immutable).merging()
    }()

    init(reportHostName: Bool = false) {
        faultInfo = FaultInfo()
        attributesSources = [ProcessorInfo(reportHostName: reportHostName),
                             Device(),
                             ScreenInfo(),
                             LocaleInfo(),
                             NetworkInfo(),
                             LibInfo(),
                             LocationInfo(),
                             faultInfo,
                             MetricsInfo(),
                             BreadcrumbsInfo()]
    }
}

extension AttributesProvider: SignalContext {
    func set(faultMessage: String?) {
        self.faultInfo.faultMessage = faultMessage
    }

    var attachmentPaths: [String] {
        return allAttachments.map(\.path)
    }

    var allAttachments: Attachments {
        attachments + attributesSources.map(\.attachments).reduce([], +)
    }
    
    var scopedAttributes: Attributes {
        return immutable + attributes;
    }
    var dynamicAttributes: Attributes {
        return attributesSources.map(\.mutable).merging()
    }

    var allAttributes: Attributes {
        return attributes + defaultAttributes
    }

    var defaultAttributes: Attributes {
        return immutable + dynamicAttributes
    }
}

extension AttributesProvider: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        return allAttributes.compactMap { "\($0.key): \($0.value)"}.joined(separator: "\n")
    }

    var debugDescription: String {
        return description
    }
}

extension Array where Element == [String: Any?] {
    func merging() -> [String: Any] {
        let keyValuePairs = reduce([:], +).compactMap({ (key: String, value: Any?) -> (key: String, value: Any)? in
            guard let value = value else {
                return nil
            }
            return (key, value)
        })
        return Dictionary(keyValuePairs) { (lhs, _) in lhs }
    }
}
