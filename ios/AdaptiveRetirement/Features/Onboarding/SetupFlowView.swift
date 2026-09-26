import SwiftUI

/// Splash → frosted four-step setup. The brand field stays mounted throughout;
/// the wordmark and contours fade as the frosted surface and setup content appear.
struct SetupFlowView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSplash: Bool { store.phase == .splash }

    var body: some View {
        ZStack {
            SetupAtmosphere(contours: isSplash ? 1 : 0)

            SetupFrost()
                .opacity(isSplash ? 0 : 1)

            if isSplash {
                SplashWordmark(onTap: advanceFromSplash)
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .task(id: isSplash) {
            guard isSplash, !Self.holdsSplash else { return }
            // Preview hold only; tapping advances immediately.
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            advanceFromSplash()
        }
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .accountPreview: AccountPreviewSheet().presentationDetents([.large])
            case .profilePicker: ProfilePickerSheet().presentationDetents([.large])
            default: EmptyView()
            }
        }
    }

    private func advanceFromSplash() {
        guard store.phase == .splash else { return }
        withAnimation(Motion.respecting(reduceMotion, Motion.handoff)) {
            store.onboardingStep = .profile
            store.phase = .onboarding
        }
    }

    /// `-hold 1` keeps the splash on screen for screenshots.
    private static var holdsSplash: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "hold")
        #else
        false
        #endif
    }
}

/// Setup glass tuned to the Figma frost: the field is already diffuse, so a light
/// material plus the 68% charcoal keeps the indigo haze instead of greying it out.
/// Reduce Transparency falls back to the shared opaque surface.
private struct SetupFrost: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            FrostedSetupSurface()
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(0.35)
                Palette.page.opacity(0.6)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Onboarding

struct OnboardingFlow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: OnboardingStep { store.onboardingStep }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack(alignment: .top) {
                stepContent
                    .id(step)
                    .transition(transition(for: step))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            actions
        }
        .padding(.horizontal, SetupStyle.gutter)
        .overlayPreferenceValue(SetupSlotKey.self) { slots in
            GeometryReader { proxy in
                continuityLayer(slots: slots, proxy: proxy)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Adaptive")
                .font(SetupStyle.navTitle)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            ZStack(alignment: .trailing) {
                Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                    .font(SetupStyle.progress)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                    .opacity(step < .focus ? 1 : 0)
                    .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .accessibilityHidden(step >= .focus)
                Color.clear
                    .frame(width: 44, height: 44)
                    .setupSlot(Slot.headerAvatar)
            }
        }
        .frame(height: 64)
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .profile: ProfileStep(profile: store.profile)
        case .accounts: AccountsStep(profile: store.profile)
        case .focus: FocusStep(profile: store.profile, selection: store.focus, select: select)
        case .result: ResultStep(profile: store.profile, focus: store.focus)
        }
    }

    private func transition(for step: OnboardingStep) -> AnyTransition {
        switch step {
        case .focus:
            // Unselected rows fade quickly; the selected icon is carried separately.
            return .asymmetric(insertion: .opacity, removal: .opacity.animation(Motion.select))
        case .result:
            let reveal: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
            return .asymmetric(insertion: reveal.animation(Motion.reveal.delay(reduceMotion ? 0 : 0.16)),
                               removal: .opacity.animation(Motion.select))
        default:
            return .opacity
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Space.s) {
            Button(action: advance) {
                Text(primaryTitle)
                    .contentTransition(.opacity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(action: secondary) {
                Text(step == .profile ? "Use my accounts" : "Back")
                    .font(SetupStyle.secondaryAction)
                    .foregroundStyle(Palette.lavender)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .contentTransition(.opacity)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.bottom, 15)
    }

    private var primaryTitle: String {
        switch step {
        case .profile: "Continue with \(store.profile.name)"
        case .accounts: "Use sample accounts"
        case .focus: "Continue"
        case .result: "See it over time"
        }
    }

    private func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            go(to: next)
        } else {
            store.finishOnboarding()
        }
    }

    private func secondary() {
        if step == .profile {
            store.sheet = .accountPreview
        } else if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
            go(to: previous)
        }
    }

    private func go(to next: OnboardingStep) {
        withAnimation(Motion.respecting(reduceMotion, Motion.smart)) {
            store.onboardingStep = next
        }
    }

    private func select(_ focus: Focus) {
        guard focus != store.focus else { return }
        withAnimation(Motion.respecting(reduceMotion, Motion.select)) {
            store.focus = focus
        }
    }

    // MARK: Continuity layer

    /// The avatar and selected topic icon live here, above the step content, so they
    /// keep one identity while each step's layout fades around them.
    @ViewBuilder
    private func continuityLayer(slots: [String: Anchor<CGRect>], proxy: GeometryProxy) -> some View {
        let avatarSlot = Slot.avatar(for: step)
        if let anchor = slots[avatarSlot] {
            SetupAvatar(profile: store.profile)
                .place(in: proxy[anchor], baseSize: SetupAvatar.baseSize)
                // Reduce Motion: crossfade between positions instead of travelling.
                .id(reduceMotion ? avatarSlot : Slot.headerAvatar)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("\(store.profile.name)'s profile")
        }

        if let iconSlot = Slot.icon(for: step, focus: store.focus), let anchor = slots[iconSlot] {
            TopicDisc(symbol: store.focus.setupSymbol)
                .place(in: proxy[anchor], baseSize: TopicDisc.baseSize)
                .id(reduceMotion ? "\(store.focus.rawValue)-\(iconSlot)" : store.focus.rawValue)
                .transition(.opacity.animation(Motion.select))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

enum Slot {
    static let headerAvatar = "avatar.header"

    static func avatar(for step: OnboardingStep) -> String {
        switch step {
        case .profile: "avatar.profile"
        case .accounts: "avatar.accounts"
        case .focus, .result: headerAvatar
        }
    }

    static func row(_ focus: Focus) -> String { "icon.row.\(focus.rawValue)" }
    static let resultIcon = "icon.result"

    static func icon(for step: OnboardingStep, focus: Focus) -> String? {
        switch step {
        case .focus: row(focus)
        case .result: resultIcon
        default: nil
        }
    }
}

#Preview {
    SetupFlowView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
        .onAppear(perform: FontRegistry.registerAll)
}
