import SwiftUI

/// Horizontally scrolls its text when it overflows the available width,
/// otherwise renders statically. Matches the expanded player's scrolling title
/// (see PLAN.md §0 — observed in the 15fps burst frames).
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 14, weight: .semibold)
    var color: Color = .white
    var speed: CGFloat = 24 // points per second

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: Bool { textWidth > containerWidth + 1 }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 40
            ZStack(alignment: .leading) {
                content
                    .background(widthReader)
                    .offset(x: overflow ? offset : 0)
                if overflow {
                    content.offset(x: offset + textWidth + gap)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = geo.size.width; restart(gap: gap) }
            .onChange(of: geo.size.width) { _, w in containerWidth = w; restart(gap: gap) }
            .onChange(of: text) { _, _ in restart(gap: gap) }
        }
    }

    private var content: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    private var widthReader: some View {
        GeometryReader { g in
            Color.clear.onAppear { textWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in textWidth = w }
        }
    }

    private func restart(gap: CGFloat) {
        offset = 0
        guard overflow else { return }
        let distance = textWidth + gap
        withAnimation(.linear(duration: Double(distance / speed)).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}
