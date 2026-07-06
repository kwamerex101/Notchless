import Foundation

/// Local 72-hour trial clock and license flag (Phase 12 scaffold). A real build
/// would validate licenses against a server (Paddle / LemonSqueezy) and sign the
/// trial start; this is the local shell only.
@MainActor
final class TrialManager: ObservableObject {
    static let shared = TrialManager()

    private let defaults = UserDefaults.standard
    private let trialLength: TimeInterval = 72 * 3600

    @Published private(set) var isLicensed: Bool
    @Published private(set) var trialStart: Date

    private init() {
        isLicensed = defaults.bool(forKey: "isLicensed")
        if let stored = defaults.object(forKey: "trialStart") as? Date {
            trialStart = stored
        } else {
            trialStart = Date()
            defaults.set(trialStart, forKey: "trialStart")
        }
    }

    var trialExpiry: Date { trialStart.addingTimeInterval(trialLength) }

    var trialRemaining: TimeInterval { max(0, trialExpiry.timeIntervalSinceNow) }

    var isTrialActive: Bool { trialRemaining > 0 }

    var isUsable: Bool { isLicensed || isTrialActive }

    var statusText: String {
        if isLicensed { return "Licensed" }
        if isTrialActive {
            let hours = Int(trialRemaining / 3600)
            return "Trial — \(hours)h remaining"
        }
        return "Trial expired"
    }

    func activate(licenseKey: String) {
        // Placeholder: accept any non-empty key locally.
        guard !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLicensed = true
        defaults.set(true, forKey: "isLicensed")
    }

    func resetTrial() {
        trialStart = Date()
        defaults.set(trialStart, forKey: "trialStart")
    }
}
