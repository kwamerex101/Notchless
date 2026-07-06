import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void = {}
    var startIndex: Int = 0

    @State private var index: Int
    private let steps = OnboardingStep.all

    init(onFinish: @escaping () -> Void = {}, startIndex: Int = 0) {
        self.onFinish = onFinish
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    private var step: OnboardingStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        VStack(spacing: 22) {
            PrimingIllustration(step: step)
                .frame(width: 300, height: 210)
                .padding(.top, 24)

            Text(step.title)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)

            if !step.apps.isEmpty {
                AppIconRow(step: step)
                    .padding(.horizontal, 28)
            }

            if let subtitle = step.subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 34)
            }

            Spacer(minLength: 0)

            PageDots(count: steps.count, index: index)

            Button(action: advance) {
                Text(isLast ? "Done" : "Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .liquidGlassProminentButton(tint: .teal)
            .padding(.horizontal, 34)
            .padding(.bottom, 26)
        }
        .frame(width: 420, height: 620)
        .background(.regularMaterial)
    }

    private func advance() {
        if let permission = step.permission {
            PermissionRequester.shared.request(permission)
        }
        if isLast {
            onFinish()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { index += 1 }
        }
    }
}

/// The stylized "permission dialog" mock with the privacy hand + capability
/// badge, skeleton text, and two buttons (Allow highlighted on permission steps).
struct PrimingIllustration: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.teal.gradient)
                    .frame(width: 62, height: 62)
                    .overlay(Image(systemName: "hand.raised.fill")
                        .font(.system(size: 26)).foregroundStyle(.white))
                Image(systemName: step.badgeSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(step.badgeColor))
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 2))
                    .offset(x: 6, y: 6)
            }

            VStack(spacing: 7) {
                Capsule().fill(.white.opacity(0.22)).frame(width: 150, height: 7)
                Capsule().fill(.white.opacity(0.14)).frame(width: 100, height: 7)
            }

            HStack(spacing: 12) {
                Capsule().fill(.white.opacity(0.14)).frame(width: 80, height: 20)
                Capsule().fill(step.highlightAllow ? Color.teal : .white.opacity(0.14))
                    .frame(width: 80, height: 20)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

struct AppIconRow: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(step.apps.enumerated()), id: \.offset) { i, app in
                VStack(spacing: 6) {
                    icon(for: app)
                        .frame(width: 46, height: 46)
                    Text(label(i, app))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                if i < step.apps.count - 1 {
                    Divider().frame(height: 44)
                }
            }
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(.secondary.opacity(0.25), lineWidth: 1))
    }

    private func label(_ i: Int, _ app: AppRef) -> String {
        if i < step.appLabels.count { return step.appLabels[i] }
        return app.label
    }

    @ViewBuilder private func icon(for app: AppRef) -> some View {
        switch app {
        case .bundle(let id):
            if let ns = Self.appIcon(id) {
                Image(nsImage: ns).resizable()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.secondary.opacity(0.2))
                    .overlay(Image(systemName: "app.dashed").foregroundStyle(.secondary))
            }
        case .symbol(let name):
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
                .overlay(Image(systemName: name).font(.system(size: 22)).foregroundStyle(.white))
        }
    }

    private static func appIcon(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i == index ? Color.teal : .secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
