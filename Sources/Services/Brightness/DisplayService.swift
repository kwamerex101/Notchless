import CoreGraphics
import Foundation

/// Reads display brightness via the private DisplayServices framework. Loads
/// lazily and degrades to nil if unavailable (works on Apple Silicon built-in
/// displays; external displays need DDC — a later phase). See PLAN.md §2, §5.
final class DisplayService {
    static let shared = DisplayService()

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private var getBrightness: GetBrightnessFn?

    private init() {
        guard let h = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ) else { return }
        if let sym = dlsym(h, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(sym, to: GetBrightnessFn.self)
        }
    }

    /// Current brightness of the main display in 0...1, or nil if unreadable.
    func brightness(for display: CGDirectDisplayID = CGMainDisplayID()) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        return getBrightness(display, &value) == 0 ? Double(value) : nil
    }
}
