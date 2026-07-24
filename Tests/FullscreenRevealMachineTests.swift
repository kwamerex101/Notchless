import XCTest
@testable import Notchless

final class FullscreenRevealMachineTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let screenFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    // Kept clear of the top band (y in [796, 800]) so band and notch-rect
    // engagement can be tested independently.
    private let notchRect = CGRect(x: 400, y: 750, width: 200, height: 32)

    private func offScreenCursor() -> CGPoint {
        CGPoint(x: 500, y: 400)
    }

    private func input(
        hidingEnabled: Bool = true,
        fullscreenActive: Bool = true,
        cursor: CGPoint,
        screenFrame: CGRect? = nil,
        notchRect: CGRect? = nil,
        content: NotchContent = .idle(.none),
        interaction: Interaction = .collapsed
    ) -> FullscreenRevealMachine.Input {
        FullscreenRevealMachine.Input(
            hidingEnabled: hidingEnabled,
            fullscreenActive: fullscreenActive,
            cursor: cursor,
            screenFrame: screenFrame ?? self.screenFrame,
            notchRect: notchRect ?? self.notchRect,
            content: content,
            interaction: interaction
        )
    }

    // MARK: - Off / idle paths

    func test_hidingDisabled_isIdle_regardlessOfCursor() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(
            input(hidingEnabled: false, cursor: CGPoint(x: 500, y: 799)),
            now: base
        )
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_fullscreenInactive_isIdle() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(
            input(fullscreenActive: false, cursor: offScreenCursor()),
            now: base
        )
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    // MARK: - Entering fullscreen with nothing engaging

    func test_fullscreenAndHiding_cursorFarFromTop_isHidden() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertEqual(output, .init(alpha: 0, allowsInteraction: false, graceDeadline: nil))
    }

    // MARK: - Band hit testing

    func test_cursorEntersBand_atLeftEdge_revealsNotch() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: CGPoint(x: 0, y: 799)), now: base)
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_cursorEntersBand_atCentre_revealsNotch() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: CGPoint(x: 500, y: 799)), now: base)
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_cursorEntersBand_atRightEdge_revealsNotch() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: CGPoint(x: 999, y: 799)), now: base)
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_cursorOnePointBelowBand_doesNotReveal() {
        var machine = FullscreenRevealMachine()
        // Band spans [796, 800]; one point below it is y = 795.
        let output = machine.update(input(cursor: CGPoint(x: 500, y: 795)), now: base)
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertEqual(output.alpha, 0)
        XCTAssertFalse(output.allowsInteraction)
    }

    func test_cursorInNotchRect_butNotBand_revealsNotch() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: CGPoint(x: 450, y: 765)), now: base)
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_bandHitTest_respectsNonZeroScreenOrigin() {
        var machine = FullscreenRevealMachine()
        let shiftedScreen = CGRect(x: 1920, y: -200, width: 1000, height: 800)
        let shiftedNotchRect = CGRect(x: 2320, y: 580, width: 200, height: 32)
        // Top band for this screen is y in [396, 400] (maxY = -200 + 800 = 600... )
        // screenFrame.maxY = -200 + 800 = 600, so band is y in [596, 600].
        let cursorInBand = CGPoint(x: 1920, y: 599)
        let output = machine.update(
            input(cursor: cursorInBand, screenFrame: shiftedScreen, notchRect: shiftedNotchRect),
            now: base
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))

        // A point that would be "in band" for the main-screen geometry but is
        // outside this shifted screen's actual band must not reveal.
        var missMachine = FullscreenRevealMachine()
        let missOutput = missMachine.update(
            input(cursor: CGPoint(x: 500, y: 799), screenFrame: shiftedScreen, notchRect: shiftedNotchRect),
            now: base
        )
        XCTAssertEqual(missMachine.state, .hidden)
        XCTAssertEqual(missOutput.alpha, 0)
    }

    // MARK: - Grace period

    func test_revealedThenCursorLeaves_staysRevealedBeforeDeadline_hiddenAtDeadline() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: CGPoint(x: 500, y: 799)), now: base)
        XCTAssertEqual(machine.state, .revealed)

        let disengaged = input(cursor: offScreenCursor())
        // First disengaged observation starts the grace window: deadline = now + grace.
        let firstDisengage = machine.update(disengaged, now: base)
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(firstDisengage.graceDeadline, base.addingTimeInterval(0.4))

        let beforeDeadline = machine.update(disengaged, now: base.addingTimeInterval(0.39))
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(beforeDeadline.alpha, 1)
        XCTAssertTrue(beforeDeadline.allowsInteraction)
        XCTAssertEqual(beforeDeadline.graceDeadline, base.addingTimeInterval(0.4))

        let atDeadline = machine.update(disengaged, now: base.addingTimeInterval(0.4))
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertEqual(atDeadline, .init(alpha: 0, allowsInteraction: false, graceDeadline: nil))
    }

    func test_graceDeadline_doesNotRestart_onRepeatedDisengagedUpdates() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: CGPoint(x: 500, y: 799)), now: base)

        let disengaged = input(cursor: offScreenCursor())
        let first = machine.update(disengaged, now: base)
        let second = machine.update(disengaged, now: base.addingTimeInterval(0.3))

        XCTAssertEqual(first.graceDeadline, base.addingTimeInterval(0.4))
        XCTAssertEqual(second.graceDeadline, base.addingTimeInterval(0.4))
    }

    func test_reengagingDuringGrace_clearsDeadline() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: CGPoint(x: 500, y: 799)), now: base)
        _ = machine.update(input(cursor: offScreenCursor()), now: base)

        let reengaged = machine.update(input(cursor: CGPoint(x: 500, y: 799)), now: base.addingTimeInterval(0.05))
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertNil(reengaged.graceDeadline)

        // Disengaging again should start a fresh grace window from this point.
        let disengagedAgain = machine.update(input(cursor: offScreenCursor()), now: base.addingTimeInterval(0.1))
        XCTAssertEqual(disengagedAgain.graceDeadline, base.addingTimeInterval(0.1 + 0.4))
    }

    // MARK: - Content-driven reveal

    func test_hudContent_drivesRevealed_fromHidden_cursorNowhereNear() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)

        let output = machine.update(
            input(cursor: offScreenCursor(), content: .hud(.sound(level: 0.5, muted: false))),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_transientNotification_drivesRevealed_fromHidden() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)

        let notification = TransientNotification(
            systemImage: "battery.100",
            tint: .green,
            title: "Battery",
            subtitle: nil,
            trailingText: nil
        )
        let output = machine.update(
            input(cursor: offScreenCursor(), content: .notification(notification)),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_expandedInteraction_holdsRevealed_noDeadline() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: CGPoint(x: 500, y: 799)), now: base)
        XCTAssertEqual(machine.state, .revealed)

        let output = machine.update(
            input(cursor: offScreenCursor(), interaction: .expanded),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_expandedContent_holdsRevealed_noDeadline() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: CGPoint(x: 500, y: 799)), now: base)
        XCTAssertEqual(machine.state, .revealed)

        let output = machine.update(
            input(cursor: offScreenCursor(), content: .expanded(.playing)),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_dictationContent_drivesRevealed_fromHidden_cursorNowhereNear() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)

        let output = machine.update(
            input(cursor: offScreenCursor(), content: .dictation(.recording)),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_mirrorContent_drivesRevealed_fromHidden_cursorNowhereNear() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)

        let output = machine.update(
            input(cursor: offScreenCursor(), content: .mirror),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_expandedFileTrayContent_drivesRevealed_fromHidden_cursorNowhereNear() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)

        let output = machine.update(
            input(cursor: offScreenCursor(), content: .fileTray(expanded: true)),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_collapsedFileTrayContent_doesNotHoldOpen_staysHidden() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)

        let output = machine.update(
            input(cursor: offScreenCursor(), content: .fileTray(expanded: false)),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertEqual(output, .init(alpha: 0, allowsInteraction: false, graceDeadline: nil))
    }

    // MARK: - Band top-edge inclusivity (Bug 2)

    func test_cursorAtExactScreenMaxY_revealsNotch() {
        // A cursor slammed to the top edge reports exactly screenFrame.maxY
        // (the same gesture that summons the menu bar). `CGRect.contains` is
        // half-open at maxY, so a naive `band.contains(cursor)` would miss
        // this and never reveal.
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: CGPoint(x: 500, y: 800)), now: base)
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_cursorAtBandLowerBoundary_revealsNotch() {
        // Band is [maxY - bandHeight, maxY] = [796, 800]; 796 is the inclusive
        // lower boundary.
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: CGPoint(x: 500, y: 796)), now: base)
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    func test_cursorJustBelowBandLowerBoundary_doesNotReveal() {
        var machine = FullscreenRevealMachine()
        let output = machine.update(input(cursor: CGPoint(x: 500, y: 795)), now: base)
        XCTAssertEqual(machine.state, .hidden)
        XCTAssertEqual(output.alpha, 0)
        XCTAssertFalse(output.allowsInteraction)
    }

    func test_cursorAtExactMaxY_nonZeroOriginScreen_revealsNotch() {
        // Same boundary check on a screen that isn't the main display, so
        // nothing here is accidentally hardcoded to origin-(0,0) geometry.
        // The cursor's x sits outside `notchRect` so this exercises the band
        // check in isolation, not the (already-correct) notch-rect check.
        var machine = FullscreenRevealMachine()
        let shiftedScreen = CGRect(x: 1920, y: -200, width: 1000, height: 800)
        let shiftedNotchRect = CGRect(x: 2320, y: 580, width: 200, height: 32)
        // screenFrame.maxY = -200 + 800 = 600.
        let output = machine.update(
            input(cursor: CGPoint(x: 1920, y: 600), screenFrame: shiftedScreen, notchRect: shiftedNotchRect),
            now: base
        )
        XCTAssertEqual(machine.state, .revealed)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }

    // MARK: - Leaving fullscreen

    func test_leavingFullscreen_fromHidden_returnsToIdle_alphaOne() {
        var machine = FullscreenRevealMachine()
        _ = machine.update(input(cursor: offScreenCursor()), now: base)
        XCTAssertEqual(machine.state, .hidden)

        let output = machine.update(
            input(fullscreenActive: false, cursor: offScreenCursor()),
            now: base.addingTimeInterval(1)
        )
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(output, .init(alpha: 1, allowsInteraction: true, graceDeadline: nil))
    }
}
