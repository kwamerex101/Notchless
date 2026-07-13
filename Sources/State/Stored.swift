import Combine
import Foundation

/// A value type that `@Stored` knows how to persist to `UserDefaults` / the
/// iCloud key-value store. Conform `Bool`, `Int`, `Double`, `String` are
/// conformed to below; `RawRepresentable` enums with a `String` or `Int`
/// `RawValue` pick up a default conformance and only need to declare
/// `: StoredValue` on the type (see `TestRawEnum` in `StoredTests.swift`).
protocol StoredValue {
    /// Decode `self` from whatever `UserDefaults`/`KeyValueStore` handed
    /// back for a key (or `nil`/mismatched type if the key is absent).
    static func storedValue(from raw: Any?, default defaultValue: Self) -> Self

    /// The `Any` representation written to `UserDefaults`/`KeyValueStore`.
    var storedRepresentation: Any { get }
}

extension Bool: StoredValue {
    static func storedValue(from raw: Any?, default defaultValue: Bool) -> Bool { (raw as? Bool) ?? defaultValue }
    var storedRepresentation: Any { self }
}

extension Int: StoredValue {
    static func storedValue(from raw: Any?, default defaultValue: Int) -> Int { (raw as? Int) ?? defaultValue }
    var storedRepresentation: Any { self }
}

extension Double: StoredValue {
    static func storedValue(from raw: Any?, default defaultValue: Double) -> Double { (raw as? Double) ?? defaultValue }
    var storedRepresentation: Any { self }
}

extension String: StoredValue {
    static func storedValue(from raw: Any?, default defaultValue: String) -> String { (raw as? String) ?? defaultValue }
    var storedRepresentation: Any { self }
}

extension StoredValue where Self: RawRepresentable, RawValue == String {
    static func storedValue(from raw: Any?, default defaultValue: Self) -> Self {
        guard let rawString = raw as? String, let value = Self(rawValue: rawString) else { return defaultValue }
        return value
    }
    var storedRepresentation: Any { rawValue }
}

extension StoredValue where Self: RawRepresentable, RawValue == Int {
    static func storedValue(from raw: Any?, default defaultValue: Self) -> Self {
        guard let rawInt = raw as? Int, let value = Self(rawValue: rawInt) else { return defaultValue }
        return value
    }
    var storedRepresentation: Any { rawValue }
}

/// Conformance required of any class hosting `@Stored` properties: it must
/// publish changes the standard `ObservableObject` way and expose the
/// injected `UserDefaults`/`KeyValueStore` the wrapper reads/writes through.
protocol StoredHost: AnyObject, ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var defaults: UserDefaults { get }
    var kvs: KeyValueStore { get }
}

/// A property wrapper that collapses the persist/load/cloud-mirror
/// boilerplate `SettingsStore` hand-wrote per preference into one
/// declaration:
///
///     @Stored("some.key", default: false) var flag: Bool
///
/// Uses the enclosing-instance `static subscript` form (like `@Published`)
/// so it can call `objectWillChange.send()` and read the host's injected
/// `defaults`/`kvs` rather than owning its own storage.
@propertyWrapper
struct Stored<Value: StoredValue> {
    fileprivate let key: String
    fileprivate let defaultValue: Value

    init(wrappedValue defaultValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = defaultValue
    }

    init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @available(*, unavailable, message: "@Stored can only be used on properties of a StoredHost class")
    var wrappedValue: Value {
        get { fatalError("@Stored must be used on a StoredHost") }
        set { fatalError("@Stored must be used on a StoredHost") }
    }

    var projectedValue: Stored<Value> { self }

    static subscript<EnclosingSelf: StoredHost>(
        _enclosingInstance instance: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Self>
    ) -> Value {
        get {
            let wrapper = instance[keyPath: storageKeyPath]
            return Value.storedValue(from: instance.defaults.object(forKey: wrapper.key), default: wrapper.defaultValue)
        }
        set {
            let wrapper = instance[keyPath: storageKeyPath]
            instance.objectWillChange.send()
            instance.defaults.set(newValue.storedRepresentation, forKey: wrapper.key)
            instance.kvs.set(newValue.storedRepresentation, forKey: wrapper.key)
        }
    }

    /// Applies an inbound cloud value (e.g. from a future `cloudChanged`
    /// handler) directly into `defaults` and publishes the change, WITHOUT
    /// mirroring back to `kvs` — the inverse of a local write, so an
    /// external change doesn't immediately echo back out to iCloud.
    func setRaw<EnclosingSelf: StoredHost>(_ value: Value, on instance: EnclosingSelf) {
        instance.objectWillChange.send()
        instance.defaults.set(value.storedRepresentation, forKey: key)
    }
}
