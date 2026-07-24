import XCTest
@testable import Notchless

final class WidgetPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WidgetPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testOpenSetRoundTrips() {
        let persistence = WidgetPersistence(defaults: defaults)
        XCTAssertEqual(persistence.openSet, [])

        persistence.openSet = [.todos, .meeting]
        XCTAssertEqual(persistence.openSet, [.todos, .meeting])
    }

    func testFrameRoundTrips() {
        let persistence = WidgetPersistence(defaults: defaults)
        XCTAssertNil(persistence.frame(for: .goals))

        let frame = CGRect(x: 12, y: 34, width: 320, height: 400)
        persistence.setFrame(frame, for: .goals)
        XCTAssertEqual(persistence.frame(for: .goals), frame)

        // Other kinds are unaffected.
        XCTAssertNil(persistence.frame(for: .todos))
    }

    func testUnknownRawValuesInPersistedOpenSetAreIgnored() {
        defaults.set(["todos", "some-future-widget-kind", "goals"], forKey: "WidgetController.openSet")

        let persistence = WidgetPersistence(defaults: defaults)
        XCTAssertEqual(persistence.openSet, [.todos, .goals])
    }
}
