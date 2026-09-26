import SwiftUI

/// Explore: the money river with a dated playhead, then the retirement comparison
/// and scenario controls. The playhead is local presentation state — it never
/// submits a scenario or changes the saved recommendation.
struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var month: Double = ExploreView.initialMonth
    @State private var isPlaying = false
    @State private var playTask: Task<Void, Never>?
    @State private var draft = ScenarioDraft.original(for: .morgan)

    private var timeline: ExploreTimeline { .illustrative(for: store.profile) }
    private var selectedMonth: Int { Int(month.rounded()) }
    private var showsHint: Bool { store.showsPlayheadHint }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your money over time.")
                    .font(.geist(16, .regular, relativeTo: .body))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, Space.s)

                riverSection

                if !showsHint {
                    RetirementComparisonSection(profile: store.profile)
                    Hairline(color: Palette.hairlineStrong)
                        .padding(.top, 17)
                        .padding(.bottom, 18)
                    ScenarioControls(profile: store.profile, draft: $draft)
                    Hairline(color: Palette.hairlineStrong)
                        .padding(.top, 19)
                        .padding(.bottom, 20)
                    OutcomeRows()
                    Button("Modeling assumptions") { store.sheet = .assumptions }
                        .font(.geist(15, .medium, relativeTo: .callout))
                        .foregroundStyle(Palette.lavender)
                        .buttonStyle(PressableStyle())
                        .frame(minHeight: 44)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(showsHint)
        .defaultScrollAnchor(Self.debugScrollAnchor)
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Explore") { HeaderAvatarButton() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsHint { hintActions }
        }
        .toolbar(showsHint ? .hidden : .visible, for: .tabBar)
        .animation(Motion.respecting(reduceMotion, Motion.smartFast), value: showsHint)
        .onChange(of: store.profile.id) { _, _ in resetForProfile() }
        .onAppear { draft = .original(for: store.profile) }
        .onDisappear(perform: pause)
    }

    // MARK: River and playhead

    private var riverSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoneyRiverView(timeline: timeline, month: month)

            transport
                .padding(.top, Space.l)

            TimelineScrubber(timeline: timeline, month: $month,
                             onInteract: userInteracted,
                             onSeek: { seek(to: $0) })
                .padding(.top, Space.l)

            Group {
                if showsHint {
                    playheadLesson
                } else {
                    milestones
                    Text("Illustrative dates and flows · not calculated results")
                        .font(.geist(11, .regular, relativeTo: .caption2))
                        .foregroundStyle(Palette.textCaption)
                        .padding(.top, Space.s)
                }
            }
            .padding(.top, Space.l)
            .transition(.opacity)

            Hairline(color: Palette.hairlineStrong)
                .padding(.vertical, Space.xl)
        }
    }

    private var transport: some View {
        HStack(alignment: .center) {
            Button(action: togglePlayback) {
                Image(systemName: playSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.lavender)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(Palette.textSecondary)
            .accessibilityLabel(playLabel)

            Spacer(minLength: Space.l)

            VStack(alignment: .trailing, spacing: 0) {
                Text(ExploreTimeline.label(forMonth: selectedMonth))
                    .font(.geist(24, .semibold, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText(value: Double(selectedMonth)))
                    .animation(reduceMotion ? nil : Motion.select, value: selectedMonth)
                Text(timeline.context(at: selectedMonth))
                    .font(.geist(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Palette.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
        }
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private var milestones: some View {
        if timeline.milestones.isEmpty {
            Text("No plan milestones in this window.")
                .font(.geist(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: 40, alignment: .topLeading)
        } else {
            HStack(alignment: .top, spacing: Space.m) {
                ForEach(timeline.milestones) { milestone in
                    Button {
                        userInteracted()
                        seek(to: milestone.month)
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(ExploreTimeline.label(forMonth: milestone.month))
                                .font(.geist(13, .medium, relativeTo: .footnote))
                                .foregroundStyle(selectedMonth == milestone.month ? Palette.lavender : Palette.textPrimary)
                            Text(milestone.title)
                                .font(.geist(11, .regular, relativeTo: .caption2))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(ExploreTimeline.spokenLabel(forMonth: milestone.month)), \(milestone.title)")
                    .accessibilityHint("Moves the playhead to this date.")
                }
            }
        }
    }

    // MARK: First-use hint

    private var playheadLesson: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Drag to a date.")
                .font(.geist(15, .semibold, relativeTo: .callout))
                .foregroundStyle(Palette.textPrimary)
            Text("See how your priorities change.\nIllustrative dates · not a forecast.")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var hintActions: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button("Start exploring") { store.showsPlayheadHint = false }
                .buttonStyle(PrimaryButtonStyle())
            Button("Back") {
                store.onboardingStep = .result
                store.phase = .onboarding
            }
            .font(.geist(15, .medium, relativeTo: .callout))
            .foregroundStyle(Palette.lavender)
            .buttonStyle(PressableStyle())
            .frame(minWidth: 72, minHeight: 44)
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.s)
        .background(Palette.page.opacity(0.001))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Playback

    private var atEnd: Bool { selectedMonth >= timeline.lastMonth }
    private var playSymbol: String { isPlaying ? "pause.fill" : (atEnd ? "arrow.counterclockwise" : "play.fill") }
    private var playLabel: String { isPlaying ? "Pause" : (atEnd ? "Replay from the opening month" : "Play to the next milestone") }

    private func togglePlayback() {
        userInteracted()
        if isPlaying { pause(); return }
        if atEnd { seek(to: 0); return }
        play(to: timeline.nextStop(after: month))
    }

    /// Advances month by month to `target`, then stops. Reduce Motion jumps with a brief crossfade.
    private func play(to target: Int) {
        guard !reduceMotion else {
            seek(to: target)
            return
        }
        isPlaying = true
        playTask = Task { @MainActor in
            var current = Int(month.rounded(.down))
            while current < target {
                try? await Task.sleep(for: .milliseconds(85))
                guard !Task.isCancelled else { return }
                current += 1
                withAnimation(.linear(duration: 0.085)) { month = Double(current) }
            }
            isPlaying = false
        }
    }

    private func pause() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    /// Any direct interaction pauses playback and retires the first-use hint.
    private func userInteracted() {
        pause()
        if store.showsPlayheadHint { store.showsPlayheadHint = false }
    }

    private func seek(to target: Int) {
        let clamped = min(max(target, 0), timeline.lastMonth)
        withAnimation(Motion.respecting(reduceMotion, Motion.smart)) { month = Double(clamped) }
    }

    private func resetForProfile() {
        pause()
        month = 0
        draft = .original(for: store.profile)
    }

    private static var debugScrollAnchor: UnitPoint? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "scroll") {
        case "bottom": return .bottom
        case "center": return .center
        default: break
        }
        #endif
        return nil
    }

    private static var initialMonth: Double {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "month"),
           let index = ExploreTimeline.monthIndex(from: value) {
            return Double(min(max(index, 0), 48))
        }
        #endif
        return 0
    }
}
