import Foundation

protocol Store {
    static func store<T>(_ value: T, forKey key: String) throws
    static func value<T>(forKey key: String) throws -> T?
    static func removeValue(forKey key: String) throws
}

struct UserDefaultsStore: Store {
    private static let userDefaults = UserDefaults.standard

    static func store<T>(_ value: T, forKey: String) {
        userDefaults.set(value, forKey: forKey)
    }

    static func value<T>(forKey key: String) -> T? {
        return userDefaults.value(forKey: key) as? T
    }

    static func removeValue(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}
