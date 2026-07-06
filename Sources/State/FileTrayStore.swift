import SwiftUI

/// Holds files dropped onto the notch (the File Tray live activity). Alcove
/// ships this as "Soon"; here it's a working shelf you can drag files into and
/// back out of.
@MainActor
final class FileTrayStore: ObservableObject {
    @Published private(set) var items: [URL] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
        }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
    }

    func clear() {
        items.removeAll()
    }
}
