import XCTest
@testable import Notchless

/// Records every `signal(_:to:)` call and returns a scriptable pid list from
/// `pids(ofProcessNamed:)`. Enumeration is synchronous here (no real process
/// spawn), so tests drive `OSDSuppressor`'s off-main hop with an injected
/// queue rather than waiting on `/usr/bin/pgrep`.
final class FakeSignaller: ProcessSignaller {
    var scriptedPIDs: [pid_t] = []
    private(set) var pidLookups = 0
    var signals: [(sig: Int32, pid: pid_t)] = []

    func pids(ofProcessNamed name: String) -> [pid_t] {
        pidLookups += 1
        return scriptedPIDs
    }

    func signal(_ sig: Int32, to pid: pid_t) {
        signals.append((sig, pid))
    }
}

final class OSDSuppressorTests: XCTestCase {
    private var signaller: FakeSignaller!
    private var suppressor: OSDSuppressor!

    @MainActor override func setUp() {
        super.setUp()
        signaller = FakeSignaller()
        // Run the enumeration hop synchronously — no real dispatch queue hop
        // — so tests can assert immediately after calling activate()/deactivate().
        suppressor = OSDSuppressor(
            signaller: signaller,
            processName: "OSDUIHelper",
            enumerationRunner: { work, completion in completion(work()) }
        )
    }

    @MainActor override func tearDown() {
        suppressor = nil
        signaller = nil
        super.tearDown()
    }

    @MainActor func testActivateSIGSTOPsEveryPIDExactlyOnceAndMarksActive() {
        signaller.scriptedPIDs = [111, 222]

        suppressor.activate()

        XCTAssertTrue(suppressor.isActive)
        XCTAssertEqual(signaller.signals.count, 2)
        XCTAssertTrue(signaller.signals.allSatisfy { $0.sig == SIGSTOP })
        XCTAssertEqual(Set(signaller.signals.map(\.pid)), Set([111, 222]))
    }

    @MainActor func testActivateTwiceDoesNotResignalAlreadySuppressedPIDs() {
        signaller.scriptedPIDs = [111, 222]

        suppressor.activate()
        suppressor.activate()

        XCTAssertEqual(signaller.signals.count, 2, "second activate() must be a no-op")
    }

    @MainActor func testDeactivateSIGCONTsEveryCachedPIDAndClearsState_secondCallIsNoOp() {
        signaller.scriptedPIDs = [111, 222]
        suppressor.activate()
        signaller.signals.removeAll()

        suppressor.deactivate()

        XCTAssertFalse(suppressor.isActive)
        XCTAssertEqual(signaller.signals.count, 2)
        XCTAssertTrue(signaller.signals.allSatisfy { $0.sig == SIGCONT })
        XCTAssertEqual(Set(signaller.signals.map(\.pid)), Set([111, 222]))

        signaller.signals.removeAll()
        suppressor.deactivate()
        XCTAssertTrue(signaller.signals.isEmpty, "second deactivate() must be a no-op")
    }

    @MainActor func testWatchdogTickSIGSTOPsOnlyTheNewPID() {
        signaller.scriptedPIDs = [111]
        suppressor.activate()
        signaller.signals.removeAll()

        signaller.scriptedPIDs = [111, 333]
        suppressor.tickWatchdogForTesting()

        XCTAssertEqual(signaller.signals.count, 1)
        XCTAssertEqual(signaller.signals.first?.sig, SIGSTOP)
        XCTAssertEqual(signaller.signals.first?.pid, 333)
    }
}
