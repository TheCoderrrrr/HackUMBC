import SwiftUI

enum AppPhase: Equatable {
    case splash
    case onboarding
    case main
}

enum OnboardingStep: Int, CaseIterable, Comparable {
    case profile, accounts, focus, result
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

enum MainTab: Hashable {
    case overview, plan, explore
}

enum ActiveSheet: String, Identifiable {
    case profilePicker, snapshot, explanation, assumptions, accountPreview
    var id: String { rawValue }
}

/// Root presentation state. Holds no financial policy.
@MainActor
final class AppStore: ObservableObject {
    @Published var phase: AppPhase = .splash
    @Published var onboardingStep: OnboardingStep = .profile
    @Published var focus: Focus = .debt
    @Published var profile: Profile = .morgan
    @Published var tab: MainTab = .overview
    @Published var sheet: ActiveSheet?
    @Published var dataMode: DataMode = .saved
    /// Explore's "Drag to a date" hint shows once after onboarding.
    @Published var showsPlayheadHint = true

    init() {
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    #if DEBUG
    /// `-screen <name>` jumps straight to a screen for previews and screenshots:
    /// splash, profile, accounts, focus, result, overview, plan, explore,
    /// and sheet names (picker, snapshot, explanation, assumptions, accountPreview).
    /// `-focus debt|cash|retirement`, `-profile morgan|jordan|casey`, `-hint 0`.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "profile"), let p = Profile.all.first(where: { $0.id == id }) { profile = p }
        if let f = defaults.string(forKey: "focus"), let value = Focus(rawValue: f) { focus = value }
        if defaults.object(forKey: "hint") != nil { showsPlayheadHint = defaults.bool(forKey: "hint") }
        guard let screen = defaults.string(forKey: "screen") else { return }
        switch screen {
        case "splash": phase = .splash
        case "profile": phase = .onboarding; onboardingStep = .profile
        case "accounts": phase = .onboarding; onboardingStep = .accounts
        case "focus": phase = .onboarding; onboardingStep = .focus
        case "result": phase = .onboarding; onboardingStep = .result
        case "overview": phase = .main; tab = .overview
        case "plan": phase = .main; tab = .plan
        case "explore": phase = .main; tab = .explore
        case "picker": phase = .main; sheet = .profilePicker
        case "snapshot": phase = .main; sheet = .snapshot
        case "explanation": phase = .main; sheet = .explanation
        case "assumptions": phase = .main; tab = .explore; sheet = .assumptions
        case "accountPreview": phase = .onboarding; onboardingStep = .profile; sheet = .accountPreview
        default: break
        }
    }
    #endif

    func select(_ profile: Profile) {
        guard profile.id != self.profile.id else { return }
        self.profile = profile
    }

    func finishOnboarding() {
        tab = .explore
        showsPlayheadHint = true
        phase = .main
    }

    func replayOnboarding() {
        onboardingStep = .profile
        focus = .debt
        phase = .onboarding
    }
}
