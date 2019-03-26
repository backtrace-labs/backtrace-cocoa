import Foundation

final class AttributesProvider {
    
    // attributes can be modified on runtime
    var userAttributes: Attributes = [:]
    
    private let bluetoothStatusListener = BluetoothStatusListener()
    private var faultMessage: String?
}

extension AttributesProvider: SignalContext {
    func set(faultMessage: String?) {
        self.faultMessage = faultMessage
    }
    
    var attributes: Attributes {
        return userAttributes + defaultAttributes
    }
    
    var defaultAttributes: Attributes {
        var defaultAttributes = DefaultAttributes.current()
        defaultAttributes["bluetooth.state"] = bluetoothStatusListener.currentState
        defaultAttributes["error.message"] = faultMessage
        return defaultAttributes
    }
}

extension AttributesProvider: CustomStringConvertible {
    var description: String {
        return attributes.compactMap { "\($0.key): \($0.value)"}.joined(separator: "\n")
    }
}
