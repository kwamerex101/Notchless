import XCTest
@testable import Notchless

@MainActor
final class ModeStoreTests: XCTestCase {
    private func tempStore() -> ModeStore {
        let suite = UserDefaults(suiteName: "modes-test-\(UUID().uuidString)")!
        return ModeStore(defaults: suite)
    }

    func test_seedsBuiltInsOnFirstRun() {
        let store = tempStore()
        XCTAssertTrue(store.modes.contains { $0.name == "Email" })
        XCTAssertTrue(store.modes.contains { $0.id == Mode.defaultID })
    }

    func test_deletedBuiltInDoesNotReappearAfterReload() {
        let suite = UserDefaults(suiteName: "modes-test-\(UUID().uuidString)")!
        let store = ModeStore(defaults: suite)
        let email = store.modes.first { $0.name == "Email" }!
        store.delete(email)
        let reloaded = ModeStore(defaults: suite)          // simulate relaunch
        XCTAssertFalse(reloaded.modes.contains { $0.name == "Email" })
    }

    func test_resolvePinBeatsAppBinding() {
        var pinned = Mode(name: "Pinned", systemImage: "star"); pinned.isEnabled = true
        var bound = Mode(name: "Bound", systemImage: "app"); bound.boundBundleIDs = ["com.apple.mail"]
        let def = Mode(id: Mode.defaultID, name: "Default", systemImage: "mic")
        let modes = [def, pinned, bound]
        let r = ModeStore.resolve(modes: modes, pinnedModeID: pinned.id, defaultID: Mode.defaultID, bundleID: "com.apple.mail")
        XCTAssertEqual(r.id, pinned.id)
    }

    func test_resolveAppBindingWhenNoPin() {
        var bound = Mode(name: "Bound", systemImage: "app"); bound.boundBundleIDs = ["com.apple.mail"]
        let def = Mode(id: Mode.defaultID, name: "Default", systemImage: "mic")
        let r = ModeStore.resolve(modes: [def, bound], pinnedModeID: nil, defaultID: Mode.defaultID, bundleID: "com.apple.mail")
        XCTAssertEqual(r.id, bound.id)
    }

    func test_resolveFallsBackToDefault() {
        let def = Mode(id: Mode.defaultID, name: "Default", systemImage: "mic")
        let r = ModeStore.resolve(modes: [def], pinnedModeID: nil, defaultID: Mode.defaultID, bundleID: "com.unknown.app")
        XCTAssertEqual(r.id, Mode.defaultID)
    }

    func test_disabledBoundModeIsSkipped() {
        var bound = Mode(name: "Bound", systemImage: "app"); bound.boundBundleIDs = ["com.apple.mail"]; bound.isEnabled = false
        let def = Mode(id: Mode.defaultID, name: "Default", systemImage: "mic")
        let r = ModeStore.resolve(modes: [def, bound], pinnedModeID: nil, defaultID: Mode.defaultID, bundleID: "com.apple.mail")
        XCTAssertEqual(r.id, Mode.defaultID)
    }
}
