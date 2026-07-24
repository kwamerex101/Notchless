import CoreGraphics
import Foundation

/// Reads and writes `WidgetController`'s persisted state — which widgets are
/// open and each one's remembered frame — to an injected `UserDefaults`.
/// Deliberately local defaults, not iCloud: window position is
/// machine-specific and syncing it would fight across a user's Macs.
///
/// Kept separate from `WidgetController` so the persistence logic is
/// testable without constructing any panel.
struct WidgetPersistence {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private let openSetKey = "WidgetController.openSet"
    private func frameKey(for kind: WidgetKind) -> String {
        "WidgetController.frame.\(kind.rawValue)"
    }

    /// The persisted open set. Unknown raw values (e.g. from a future
    /// version's widget kind) are ignored rather than crashing.
    var openSet: Set<WidgetKind> {
        get {
            let raw = defaults.stringArray(forKey: openSetKey) ?? []
            return Set(raw.compactMap(WidgetKind.init(rawValue:)))
        }
        nonmutating set {
            defaults.set(newValue.map(\.rawValue), forKey: openSetKey)
        }
    }

    /// The persisted frame for `kind`, or nil if none has been saved yet.
    func frame(for kind: WidgetKind) -> CGRect? {
        guard let dict = defaults.dictionary(forKey: frameKey(for: kind)) else { return nil }
        guard let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat,
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Persists `frame` for `kind`.
    func setFrame(_ frame: CGRect, for kind: WidgetKind) {
        defaults.set([
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height
        ], forKey: frameKey(for: kind))
    }
}
