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
            VStack(spacing: 22) {
                switch step.kind {
                case .priming:
                    PrimingIllustration(step: step)
                        .frame(width: 300, height: 210)
                        .padding(.top, 24)
                case .models:
                    OnboardingModels()
                        .padding(.horizontal, 28).padding(.top, 24)
                case .tryDictation:
                    OnboardingDictationTry()
                        .padding(.horizontal, 28).padding(.top, 24)
                }

                Text(step.title)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)

                if step.kind == .priming, !step.apps.isEmpty {
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
            }
            .id(index)
            .transition(.asymmetric(
                insertion: .push(from: .trailing).combined(with: .opacity),
                removal: .opacity.combined(with: .scale(scale: 0.96))
            ))

            Spacer(minLength: 0)

            PageDots(count: steps.count, index: index)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: index)

            Button(action: advance) {
                Text(isLast ? "Done" : "Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .liquidGlassProminentButton(tint: AppTheme.accent)
            .padding(.horizontal, 34)
            .padding(.bottom, 26)
        }
        .frame(width: 420, height: 620)
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
                Capsule().fill(.primary.opacity(0.22)).frame(width: 150, height: 7)
                Capsule().fill(.primary.opacity(0.14)).frame(width: 100, height: 7)
            }

            HStack(spacing: 12) {
                Capsule().fill(.primary.opacity(0.14)).frame(width: 80, height: 20)
                Capsule().fill(step.highlightAllow ? Color.teal : .primary.opacity(0.14))
                    .frame(width: 80, height: 20)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                     fallback: .ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(.primary.opacity(0.10), lineWidth: 1))
    }
}

struct AppIconRow: View {
    let step: OnboardingStep

    /// Pair each app with its label, then drop any real app that isn't
    /// installed — we only show icons the user actually has.
    private var items: [(app: AppRef, label: String)] {
        step.apps.enumerated().compactMap { i, app in
            let label = i < step.appLabels.count ? step.appLabels[i] : app.label
            switch app {
            case .bundle(let id):
                guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else { return nil }
            case .symbol:
                break
            }
            return (app, label)
        }
    }

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    VStack(spacing: 6) {
                        icon(for: item.app)
                            .frame(width: 46, height: 46)
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    if i < items.count - 1 {
                        Divider().frame(height: 44)
                    }
                }
            }
            .padding(.vertical, 14)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                         fallback: .thinMaterial)
        }
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

/// Onboarding page for optionally downloading on-device models. Downloads run
/// in the background so the user can keep going.
struct OnboardingModels: View {
    @ObservedObject private var parakeet = ParakeetModelStore.shared
    @ObservedObject private var llm = LLMModelStore.shared

    var body: some View {
        VStack(spacing: 12) {
            card(title: "Parakeet · Neural Engine",
                 detail: "Faster and more accurate. ~600 MB, Apple Silicon.") {
                ParakeetStatusRow(status: parakeet.status) { parakeet.preload() }
            }
            card(title: "On-device cleanup · Gemma",
                 detail: "Polish transcripts locally, no network. Optional.") {
                GemmaStatusRow(status: llm.status, sizeText: llm.selected.sizeText,
                               download: { llm.download() }, delete: { llm.delete() })
            }
        }
    }

    @ViewBuilder private func card<Content: View>(
        title: String, detail: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                     fallback: .thinMaterial)
    }
}

/// Onboarding "try it" field — a self-contained live dictation demo using Apple
/// Speech, so the user can see it work before finishing setup.
struct OnboardingDictationTry: View {
    @State private var text = ""
    @State private var isRecording = false
    @State private var level: CGFloat = 0
    @State private var transcriber = SpeechTranscriber()

    var body: some View {
        VStack(spacing: 14) {
            ScrollView {
                Text(text.isEmpty ? "Your words will appear here…" : text)
                    .font(.system(size: 13))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 96)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                         fallback: .thinMaterial)

            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    Text(isRecording ? "Stop" : "Tap to talk")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
            .liquidGlassProminentButton(tint: isRecording ? .red : AppTheme.accent)
        }
        .onDisappear { transcriber.cancel() }
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        transcriber.onPartial = { text = $0 }
        transcriber.onLevel = { level = $0 }
        isRecording = true
        Task { try? await transcriber.start() }
    }

    private func stop() {
        isRecording = false
        Task {
            let final = await transcriber.finish()
            if !final.isEmpty { text = final }
        }
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
