import XCTest
@testable import Notchless

final class DictationSizingTests: XCTestCase {
    private let metrics = NotchMetrics(notchWidth: 200, notchHeight: 32, notchCenterX: 720, screenTopY: 1000, hasRealNotch: true)

    func test_recordingSliverIsShorterThanSettledPanel() {
        let sliver = NotchSizing.size(for: .dictation(.recording), metrics: metrics, dictationSettled: false)
        let panel  = NotchSizing.size(for: .dictation(.recording), metrics: metrics, dictationSettled: true)
        XCTAssertLessThan(sliver.height, panel.height)
        XCTAssertLessThan(sliver.width, panel.width)
    }

    func test_successChipIsMoreCompactThanRecordingPanel() {
        let panel = NotchSizing.size(for: .dictation(.recording), metrics: metrics, dictationSettled: true)
        let chip  = NotchSizing.size(for: .dictation(.success("hi")), metrics: metrics)
        XCTAssertLessThan(chip.height, panel.height)
    }

    func test_settledFlagIgnoredForNonRecordingPhases() {
        let a = NotchSizing.size(for: .dictation(.transcribing), metrics: metrics, dictationSettled: false)
        let b = NotchSizing.size(for: .dictation(.transcribing), metrics: metrics, dictationSettled: true)
        XCTAssertEqual(a, b)
    }
}
