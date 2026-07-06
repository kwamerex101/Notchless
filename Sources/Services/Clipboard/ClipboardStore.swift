import AppKit
import Combine

/// In-memory recent-clipboard history. Polls the general pasteboard and keeps
/// the most recent text copies (not persisted to disk). Also hosts the
/// screen-colour picker, whose result flows back through the clipboard.
@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let date: Date
    }

    @Published private(set) var items: [Item] = []

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let cap = 20

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(Item(text: text, date: Date()), at: 0)
        if items.count > cap { items = Array(items.prefix(cap)) }
    }

    /// Re-copies an item to the pasteboard and floats it to the top.
    func copy(_ item: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastChangeCount = pb.changeCount   // avoid re-adding on the next poll
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
    }

    func clear() {
        items.removeAll()
    }

    /// Opens the macOS screen colour sampler and copies the picked hex.
    func pickColor() {
        NSColorSampler().show { color in
            guard let color else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(color.hexString, forType: .string)
        }
    }
}

extension NSColor {
    /// "#RRGGBB" in sRGB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
