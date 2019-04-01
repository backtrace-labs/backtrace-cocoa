import Foundation

final class AttributesProvider {
    
    // attributes can be modified on runtime
    var attributes: Attributes = [:]
    
    private let bluetoothStatusListener = BluetoothStatusListener()
    private var faultMessage: String?
}

extension AttributesProvider: SignalContext {
    func set(faultMessage: String?) {
        self.faultMessage = faultMessage
    }
    
    var allAttributes: Attributes {
        return attributes + defaultAttributes
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
        return allAttributes.compactMap { "\($0.key): \($0.value)"}.joined(separator: "\n")
    }
}
