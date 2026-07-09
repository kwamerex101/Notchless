import XCTest
@testable import Notchless

final class ModeTests: XCTestCase {
    private let base = EffectiveDictation(
        output: .pasteActiveApp, cleanup: .off, cleanupIntensity: .light,
        voiceCommands: false, smartFormatting: true, autoCapitalize: true,
        engine: .appleSpeech, languageID: "en_US", instruction: nil)

    func test_defaultModeInheritsEverything() {
        let def = Mode.builtIns().first { $0.id == Mode.defaultID }!
        let eff = def.applied(over: base)
        XCTAssertEqual(eff, base)                    // no overrides → identical
    }

    func test_overridesWinWhenSet() {
        var m = Mode(name: "Email", systemImage: "envelope")
        m.output = .appleNotes
        m.cleanup = .always
        m.instruction = "Rewrite as an email."
        let eff = m.applied(over: base)
        XCTAssertEqual(eff.output, .appleNotes)       // overridden
        XCTAssertEqual(eff.cleanup, .always)          // overridden
        XCTAssertEqual(eff.instruction, "Rewrite as an email.")
        XCTAssertEqual(eff.engine, .appleSpeech)      // inherited
        XCTAssertEqual(eff.smartFormatting, true)     // inherited
    }

    func test_builtInsIncludeDefaultEmailCodeNotesCasual() {
        let names = Set(Mode.builtIns().map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["Default", "Email", "Code", "Notes", "Casual"]))
    }

    func test_codableRoundTrip() throws {
        var m = Mode(name: "Code", systemImage: "chevron.left.forwardslash.chevron.right")
        m.engine = .parakeet; m.boundBundleIDs = ["com.apple.dt.xcode"]
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(Mode.self, from: data)
        XCTAssertEqual(back, m)
    }
}
