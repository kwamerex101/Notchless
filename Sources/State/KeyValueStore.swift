import Foundation

/// Abstracts the iCloud key-value store so tests can inject a fake in place
/// of `NSUbiquitousKeyValueStore`.
protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStore {}
