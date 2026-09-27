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
    @State private var isScrolled = !ScreenHeaderScroll.isTrackable
    /// Live custom-scenario result from "Compare scenario"; cleared when the draft or profile changes.
    @State private var customResult: API.Evaluation?
    /// The scenario behind `customResult`, so Scenario history saves exactly what is shown.
    @State private var customScenario: API.Scenario?
    /// A newer scenario is being calculated; the chart dims the old line meanwhile.
    @State private var scenarioUpdating = false
    /// Why the controls' scenario has no line (e.g. no live server), shown at the chart.
    @State private var scenarioNote: String?
    /// The draft is set from the profile once; returning to the tab keeps your scenario.
    @State private var draftReady = false
    @StateObject private var history = HistoryModel()

    /// The compared scenario for the chart. While the first one is still calculating there is
    /// nothing to draw yet; afterwards the previous line stays, dimmed, until the next arrives.
    private var scenarioOverlay: ScenarioOverlay? {
        if let customResult {
            return ScenarioOverlay(evaluation: customResult, scenario: customScenario,
                                   isUpdating: scenarioUpdating, note: scenarioNote)
        }
        // No result yet (first calculation in flight) or none possible: still name the
        // controls' scenario at the chart and say why there's no line.
        guard scenarioUpdating || scenarioNote != nil else { return nil }
        return ScenarioOverlay(evaluation: nil, scenario: draft.apiScenario,
                               isUpdating: scenarioUpdating, note: scenarioNote)
    }

    private var timeline: ExploreTimeline { .illustrative(for: store.displayProfile) }
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
                    RetirementComparisonSection(profile: store.displayProfile, scenario: scenarioOverlay)
                    Hairline(color: Palette.hairlineStrong)
                        .padding(.top, 17)
                        .padding(.bottom, 18)
                    ScenarioControls(profile: store.displayProfile, draft: $draft, result: $customResult,
                                     resultScenario: $customScenario, isUpdating: $scenarioUpdating,
                                     unavailableNote: $scenarioNote)
                    Hairline(color: Palette.hairlineStrong)
                        .padding(.top, 19)
                        .padding(.bottom, 20)
                    OutcomeRows(evaluation: store.displayProfile.evaluation, custom: customResult)
                    Hairline(color: Palette.hairlineStrong)
                        .padding(.top, 19)
                        .padding(.bottom, 20)
                    ScenarioHistorySection(model: history, profile: store.displayProfile,
                                           scenarioResult: customResult,
                                           scenario: customResult == nil ? nil : customScenario)
                    Button { store.sheet = .assumptions } label: {
                        Label("Modeling assumptions", systemImage: "slider.horizontal.3")
                    }
                        .font(.geist(15, .medium, relativeTo: .callout))
                        .foregroundStyle(Palette.accent)
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
        .tracksScrolled($isScrolled)
        .scrollDisabled(showsHint)
        .defaultScrollAnchor(Self.debugScrollAnchor)
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Explore", isScrolled: isScrolled) { HeaderAvatarButton() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsHint { hintActions }
        }
        .toolbar(showsHint ? .hidden : .visible, for: .tabBar)
        .animation(Motion.respecting(reduceMotion, Motion.smartFast), value: showsHint)
        .onChange(of: store.profile.id) { _, _ in resetForProfile() }
        .onAppear {
            // Only the first appearance seeds the draft; profile switches reset it via
            // resetForProfile. Re-seeding here threw away your scenario on every tab switch.
            guard !draftReady else { return }
            draftReady = true
            draft = .original(for: store.displayProfile)
            #if DEBUG
            // `-scenarioAge 69` / `-scenarioRate 10` edit the scenario controls on launch, as a
            // stepper tap would, for screenshots of the live recalculation.
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "scenarioAge") != nil { draft.retirementAge = defaults.integer(forKey: "scenarioAge"); draft.preset = nil }
            if defaults.object(forKey: "scenarioRate") != nil { draft.policy = .fixed; draft.fixedRate = defaults.double(forKey: "scenarioRate"); draft.preset = nil }
            #endif
        }
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
                    Text(store.displayProfile.evaluation == nil
                         ? "Illustrative dates and flows · not calculated results"
                         : "Milestone dates from the plan · flows illustrative")
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

    /// The playhead's date and what the plan is doing then.
    private var transport: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                WordRoll(text: ExploreTimeline.label(forMonth: selectedMonth))
                    .font(.numeral(24, .medium, relativeTo: .title2))
                    .foregroundStyle(Palette.textPrimary)
                WordRoll(text: timeline.context(at: selectedMonth))
                    .font(.geist(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Palette.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.l)
            Button(action: togglePlayback) {
                Image(systemName: playSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(Palette.textSecondary)
            .accessibilityLabel(playLabel)
            .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
        }
        .frame(minHeight: 52)
    }

    static func symbol(for milestone: Milestone) -> String {
        let title = milestone.title.lowercased()
        if title.contains("debt") { return "checkmark.seal.fill" }
        if title.contains("reserve") { return "umbrella.fill" }
        if title.contains("retire") || title.contains("contribution") { return "arrow.up.forward" }
        return "flag.fill"
    }

    @ViewBuilder
    private var milestones: some View {
        if timeline.milestones.isEmpty {
            if timeline.alreadyMet.isEmpty {
                Text("No plan milestones in this window.")
                    .font(.geist(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: 40, alignment: .topLeading)
            }
        } else {
            HStack(alignment: .top, spacing: Space.m) {
                ForEach(timeline.milestones) { milestone in
                    let isSelected = selectedMonth == milestone.month
                    Button {
                        userInteracted()
                        seek(to: milestone.month)
                    } label: {
                        HStack(alignment: .top, spacing: Space.s) {
                            Image(systemName: Self.symbol(for: milestone))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 18)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ExploreTimeline.label(forMonth: milestone.month))
                                    .font(.geist(13, .medium, relativeTo: .footnote))
                                    .foregroundStyle(isSelected ? Palette.accent : Palette.textPrimary)
                                Text(milestone.title)
                                    .font(.geist(11, .regular, relativeTo: .caption2))
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .animation(Motion.select, value: isSelected)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(ExploreTimeline.spokenLabel(forMonth: milestone.month)), \(milestone.title)")
                    .accessibilityHint("Moves the playhead to this date.")
                }
            }
        }
        if !timeline.alreadyMet.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 18)
                (Text("Already met: ").font(.geist(12, .medium, relativeTo: .caption))
                 + Text(timeline.alreadyMet.joined(separator: " · ")).font(.geist(12, .regular, relativeTo: .caption)))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, timeline.milestones.isEmpty ? 0 : Space.s)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: First-use hint

    private var playheadLesson: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Drag to a date.")
                .font(.geist(15, .medium, relativeTo: .callout))
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
            .foregroundStyle(Palette.accent)
            .buttonStyle(PressableStyle())
            .frame(minWidth: 72, minHeight: 44)
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.s)
        .background(Palette.page.opacity(0.001))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Scrubbing

    private var atEnd: Bool { selectedMonth >= timeline.lastMonth }
    private var playSymbol: String { isPlaying ? "pause.fill" : (atEnd ? "arrow.counterclockwise" : "play.fill") }
    private var playLabel: String { isPlaying ? "Pause" : (atEnd ? "Replay from the opening month" : "Play the timeline") }

    private func togglePlayback() {
        userInteracted()
        if isPlaying { pause(); return }
        if atEnd { seek(to: 0); return }
        play(to: timeline.lastMonth)
    }

    /// Seconds of playback per month: the four-year window's pace, sped up for longer windows
    /// so a full sweep never takes more than about eight seconds.
    private var secondsPerMonth: Double { min(0.11, 8.0 / Double(max(timeline.lastMonth, 1))) }

    /// Sweeps continuously to `target`, a frame at a time, so the river and playhead never
    /// stop at milestones. Reduce Motion jumps with a brief crossfade.
    private func play(to target: Int) {
        guard !reduceMotion else {
            seek(to: target)
            return
        }
        isPlaying = true
        let startMonth = month
        let distance = Double(target) - startMonth
        playTask = Task { @MainActor in
            let clock = ContinuousClock()
            let start = clock.now
            while !Task.isCancelled {
                let elapsed = start.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let next = min(startMonth + seconds / secondsPerMonth, Double(target))
                month = next
                if next >= Double(target) || distance <= 0 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled { isPlaying = false }
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
        draft = .original(for: store.displayProfile)
        customResult = nil
        customScenario = nil
        scenarioUpdating = false
        scenarioNote = nil
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
