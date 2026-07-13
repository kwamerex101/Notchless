import XCTest
import Combine
@testable import Notchless

/// Dictionary-backed fake for `KeyValueStore` so tests never touch the real
/// iCloud key-value store.
final class FakeKVS: KeyValueStore {
    private(set) var storage: [String: Any] = [:]
    private(set) var setKeys: [String] = []

    func object(forKey key: String) -> Any? { storage[key] }

    func set(_ value: Any?, forKey key: String) {
        setKeys.append(key)
        storage[key] = value
    }

    @discardableResult func synchronize() -> Bool { true }
}

enum TestRawEnum: String, StoredValue {
    case alpha
    case beta
}

/// Minimal host so tests don't have to invoke SettingsStore's heavy init.
final class TestHost: StoredHost {
    let defaults: UserDefaults
    let kvs: KeyValueStore

    init(defaults: UserDefaults, kvs: KeyValueStore) {
        self.defaults = defaults
        self.kvs = kvs
    }

    @Stored("test.flag", default: false) var flag: Bool
    @Stored("test.count", default: 3) var count: Int
    @Stored("test.rawEnum", default: TestRawEnum.alpha) var rawEnum: TestRawEnum
}

final class StoredTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var kvs: FakeKVS!

    override func setUp() {
        super.setUp()
        suiteName = "StoredTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        kvs = FakeKVS()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        kvs = nil
        suiteName = nil
        super.tearDown()
    }

    func test_readsDefaultWhenKeyAbsent() {
        let host = TestHost(defaults: defaults, kvs: kvs)
        XCTAssertEqual(host.flag, false)
        XCTAssertEqual(host.count, 3)
    }

    func test_writingPersistsToDefaultsAndMirrorsToKVS() {
        let host = TestHost(defaults: defaults, kvs: kvs)
        host.flag = true
        host.count = 42

        XCTAssertEqual(defaults.bool(forKey: "test.flag"), true)
        XCTAssertEqual(defaults.integer(forKey: "test.count"), 42)
        XCTAssertEqual(kvs.storage["test.flag"] as? Bool, true)
        XCTAssertEqual(kvs.storage["test.count"] as? Int, 42)
    }

    func test_secondHostOverSameSuiteReadsPersistedValue() {
        let host1 = TestHost(defaults: defaults, kvs: kvs)
        host1.flag = true
        host1.count = 7

        let host2 = TestHost(defaults: defaults, kvs: FakeKVS())
        XCTAssertEqual(host2.flag, true)
        XCTAssertEqual(host2.count, 7)
    }

    func test_setRawAppliesInboundValueWithoutWritingToKVS() {
        let host = TestHost(defaults: defaults, kvs: kvs)
        host.$flag.setRaw(true, on: host)

        XCTAssertEqual(host.flag, true)
        XCTAssertFalse(kvs.setKeys.contains("test.flag"))
    }

    func test_rawRepresentableStringEnumRoundTrips() {
        let host = TestHost(defaults: defaults, kvs: kvs)
        XCTAssertEqual(host.rawEnum, .alpha)

        host.rawEnum = .beta
        XCTAssertEqual(defaults.string(forKey: "test.rawEnum"), "beta")

        let host2 = TestHost(defaults: defaults, kvs: FakeKVS())
        XCTAssertEqual(host2.rawEnum, .beta)
    }
}
