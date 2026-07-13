import XCTest
@testable import Notchless

/// Unit tests for the PURE `ExternalBrightnessBridge.command(for:level:displayArg:)`
/// builder only. Tool detection and actual `Process` invocation are on-device
/// concerns (they touch the filesystem / spawn processes) and are deliberately
/// not covered here — see the P2b report for what remains unverified.
final class ExternalBrightnessTests: XCTestCase {
    func test_lunar_buildsBrightnessCommand() {
        let cmd = ExternalBrightnessBridge.command(for: .lunar, level: 0.5, displayArg: "main")
        XCTAssertEqual(cmd.launchPath, ExternalBrightnessBridge.lunarCLIPath)
        XCTAssertTrue(cmd.args.contains("brightness"))
        XCTAssertTrue(cmd.args.contains("50"))
    }

    func test_betterDisplay_buildsBrightnessCommand() {
        let cmd = ExternalBrightnessBridge.command(for: .betterDisplay, level: 0.8, displayArg: "1")
        XCTAssertTrue(ExternalBrightnessBridge.betterDisplayCLIPaths.contains(cmd.launchPath))
        XCTAssertTrue(cmd.args.contains { $0.hasPrefix("-brightness=") && $0.contains("0.8") })
        XCTAssertTrue(cmd.args.contains("-display=1"))
    }

    func test_clamp_upperBound() {
        let lunarCmd = ExternalBrightnessBridge.command(for: .lunar, level: 1.5, displayArg: "main")
        XCTAssertTrue(lunarCmd.args.contains("100"))

        let bdCmd = ExternalBrightnessBridge.command(for: .betterDisplay, level: 1.5, displayArg: "main")
        XCTAssertTrue(bdCmd.args.contains { arg in
            guard arg.hasPrefix("-brightness=") else { return false }
            let value = arg.replacingOccurrences(of: "-brightness=", with: "")
            return Double(value) == 1.0
        })
    }

    func test_clamp_lowerBound() {
        let lunarCmd = ExternalBrightnessBridge.command(for: .lunar, level: -0.2, displayArg: "main")
        XCTAssertTrue(lunarCmd.args.contains("0"))

        let bdCmd = ExternalBrightnessBridge.command(for: .betterDisplay, level: -0.2, displayArg: "main")
        XCTAssertTrue(bdCmd.args.contains { arg in
            guard arg.hasPrefix("-brightness=") else { return false }
            let value = arg.replacingOccurrences(of: "-brightness=", with: "")
            return Double(value) == 0.0
        })
    }
}
