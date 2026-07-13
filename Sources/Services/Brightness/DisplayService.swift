import CoreGraphics
import Foundation

/// Reads display brightness via the private DisplayServices framework. Loads
/// lazily and degrades to nil if unavailable (works on Apple Silicon built-in
/// displays; external displays need DDC — a later phase). See PLAN.md §2, §5.
final class DisplayService {
    static let shared = DisplayService()

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private var getBrightness: GetBrightnessFn?

    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private var setBrightnessFn: SetBrightnessFn?

    private init() {
        guard let h = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ) else { return }
        if let sym = dlsym(h, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(sym, to: GetBrightnessFn.self)
        }
        if let sym = dlsym(h, "DisplayServicesSetBrightness") {
            setBrightnessFn = unsafeBitCast(sym, to: SetBrightnessFn.self)
        }
    }

    /// Current brightness of the main display in 0...1, or nil if unreadable.
    func brightness(for display: CGDirectDisplayID = CGMainDisplayID()) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(display, &value) == 0 ? Double(value) : nil
    }

    /// Whether the built-in brightness setter is available AND the display is built-in.
    static func canSetBrightness(symbolAvailable: Bool, isBuiltIn: Bool) -> Bool {
        symbolAvailable && isBuiltIn
    }

    var setterAvailable: Bool { setBrightnessFn != nil }

    func isBuiltIn(_ display: CGDirectDisplayID = CGMainDisplayID()) -> Bool {
        CGDisplayIsBuiltin(display) != 0
    }

    /// Sets built-in display brightness (0...1 clamped). Returns true on success.
    /// No-op → false if the setter symbol is unavailable or the display isn't built-in.
    @discardableResult
    func setBrightness(_ level: Double, for display: CGDirectDisplayID = CGMainDisplayID()) -> Bool {
        guard DisplayService.canSetBrightness(symbolAvailable: setterAvailable, isBuiltIn: isBuiltIn(display)) else {
            return false
        }
        let clampedLevel = min(max(level, 0), 1)
        return setBrightnessFn?(display, Float(clampedLevel)) == 0
    }
}
