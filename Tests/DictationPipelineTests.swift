import XCTest
@testable import Notchless

/// Pure text-pipeline transforms that shape dictation output — previously
/// untested despite directly affecting what gets typed.
final class DictationPipelineTests: XCTestCase {
    // MARK: BuiltinTransforms

    func test_spokenOperators() {
        XCTAssertEqual(BuiltinTransforms.apply("i love c plus plus"), "i love C++")
        XCTAssertEqual(BuiltinTransforms.apply("write c sharp code"), "write C# code")
        XCTAssertEqual(BuiltinTransforms.apply("counter plus plus"), "counter ++")
    }

    func test_semverJoins() {
        XCTAssertEqual(BuiltinTransforms.apply("version 1 dot 0 dot 29"), "version 1.0.29")
        XCTAssertEqual(BuiltinTransforms.apply("build 1.0.29 plus 230"), "build 1.0.29+230")
    }

    func test_collapseRepeatsHonorsAllowlist() {
        XCTAssertEqual(BuiltinTransforms.apply("the the plan"), "the plan")
        // Legitimately-doubled words survive.
        XCTAssertEqual(BuiltinTransforms.apply("i had had enough"), "i had had enough")
        XCTAssertEqual(BuiltinTransforms.apply("that that thing"), "that that thing")
    }

    // MARK: TranscriptHygiene

    func test_hygieneStripsMarkersAndCollapsesSpace() {
        XCTAssertEqual(TranscriptHygiene.clean("hello [BLANK_AUDIO] world"), "hello world")
        XCTAssertEqual(TranscriptHygiene.clean("[silence]"), "")
        XCTAssertEqual(TranscriptHygiene.clean("  spaced   out  "), "spaced out")
    }

    func test_stripsLeakedModelTokens() {
        // The exact ChatML stop-token leak seen from the on-device cleanup model.
        XCTAssertEqual(
            TranscriptHygiene.stripModelTokens("They're not doing any work. I don't know.<|im_end|>"),
            "They're not doing any work. I don't know.")
        // Timeout-truncated variant (decode stopped mid-token).
        XCTAssertEqual(TranscriptHygiene.stripModelTokens("Hello there.<|im_en"), "Hello there.")
        // Gemma end-of-turn marker.
        XCTAssertEqual(TranscriptHygiene.stripModelTokens("Clean text.<end_of_turn>"), "Clean text.")
        // Untouched when there's nothing to strip.
        XCTAssertEqual(TranscriptHygiene.stripModelTokens("No tokens here."), "No tokens here.")
    }

    // MARK: CleanupGate

    func test_needsCleanup() {
        XCTAssertFalse(CleanupGate.needsCleanup("   "))                     // empty
        XCTAssertTrue(CleanupGate.needsCleanup("um the plan is ready."))    // filler
        XCTAssertTrue(CleanupGate.needsCleanup("the the plan is ready."))   // repeat
        XCTAssertTrue(CleanupGate.needsCleanup("this is a long sentence without punctuation")) // no terminal punct, >3 words
        XCTAssertTrue(CleanupGate.needsCleanup("lowercase start."))         // lowercase first
        XCTAssertFalse(CleanupGate.needsCleanup("All good."))               // clean
    }

    // MARK: SpokenCommands

    func test_spokenFormatting() {
        let out = SpokenCommands.apply("line one new line line two")
        XCTAssertTrue(out.contains("line one\n"))
        XCTAssertTrue(out.contains("line two"))
        XCTAssertTrue(SpokenCommands.apply("a new paragraph b").contains("\n\n"))
    }

    func test_scratchThatDropsPrecedingSentence() {
        // Removes the sentence before "scratch that", keeps the rest.
        let out = SpokenCommands.apply("First sentence. Second one. scratch that Third.")
        XCTAssertTrue(out.hasPrefix("First sentence."))
        XCTAssertTrue(out.contains("Third."))
        XCTAssertFalse(out.contains("Second one"))
    }
}
