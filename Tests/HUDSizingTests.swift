import XCTest
import CoreAudio
@testable import Notchless

final class HUDSizingTests: XCTestCase {
    func test_hudWidth_noOptions_equalsBase() {
        let options = HUDOptions(showMuteAsEmpty: true, showPercentageLabel: false, showOutputDevice: false)
        let width = NotchSizing.hudWidth(base: 300, kind: .sound(level: 0.5, muted: false), options: options)
        XCTAssertEqual(width, 300)
    }

    func test_hudWidth_addsPercentagePadding() {
        let options = HUDOptions(showMuteAsEmpty: true, showPercentageLabel: true, showOutputDevice: false)
        let width = NotchSizing.hudWidth(base: 300, kind: .sound(level: 0.5, muted: false), options: options)
        XCTAssertEqual(width, 344)
    }

    func test_hudWidth_addsOutputGlyphPadding_soundOnly() {
        let options = HUDOptions(showMuteAsEmpty: true, showPercentageLabel: false, showOutputDevice: true)
        let soundWidth = NotchSizing.hudWidth(base: 300, kind: .sound(level: 0.5, muted: false), options: options)
        let displayWidth = NotchSizing.hudWidth(base: 300, kind: .display(level: 0.5), options: options)
        XCTAssertEqual(soundWidth, 326)
        XCTAssertEqual(displayWidth, 300)
    }

    func test_symbolForTransportType_mapsKnownTypes() {
        XCTAssertEqual(AudioOutputService.symbol(forTransportType: kAudioDeviceTransportTypeBuiltIn), "speaker.wave.2.fill")
        XCTAssertEqual(AudioOutputService.symbol(forTransportType: kAudioDeviceTransportTypeUSB), "headphones")
        XCTAssertEqual(AudioOutputService.symbol(forTransportType: kAudioDeviceTransportTypeBluetooth), "airpods")
        XCTAssertEqual(AudioOutputService.symbol(forTransportType: 0xFFFF_FFFF), "speaker.wave.2.fill")
    }
}
