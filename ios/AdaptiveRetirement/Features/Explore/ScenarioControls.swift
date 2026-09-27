import SwiftUI

/// Draft comparison settings. Local presentation state: editing never changes the
/// saved recommendation, and nothing here is calculated in Swift.
struct ScenarioDraft: Equatable {
    enum Policy: String, CaseIterable, Identifiable {
        case adaptive = "Adaptive"
        case fixed = "Fixed rate"
        var id: String { rawValue }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case original, retireLater, ratePlusOne
        var id: String { rawValue }

        var demoPreset: DemoPreset {
            switch self {
            case .original: .original
            case .retireLater: .retirePlusTwo
            case .ratePlusOne: .contributionPlusOne
            }
        }
    }

    var retirementAge: Int
    var policy: Policy = .adaptive
    /// Employee rate in percent, 0…20 in 0.5 steps, used when `policy == .fixed`.
    var fixedRate: Double
    var extraDebtDollars: String = ""
    var priorityStyle: API.PlanningPreference? = nil
    var preset: Preset? = .original

    /// The fields that change the request; `preset` is only a chip highlight, so editing a
    /// control and reverting it no longer sends an identical request (REPORT E2).
    var requestShape: RequestShape { RequestShape(age: retirementAge, policy: policy, rate: fixedRate,
                                                   extraDebt: extraDebtDollars, priorityStyle: priorityStyle) }

    struct RequestShape: Equatable {
        let age: Int
        let policy: Policy
        let rate: Double
        let extraDebt: String
        let priorityStyle: API.PlanningPreference?
    }

    /// The `/v1/evaluate` scenario this draft asks for.
    var apiScenario: API.Scenario {
        API.Scenario(retirementAge: retirementAge, employeeContributionRate: policy == .fixed ? fixedRate / 100 : nil,
                     extraMonthlyDebtCents: extraDebtDollars.isEmpty ? nil : Int64(((Double(extraDebtDollars) ?? 0) * 100).rounded()),
                     priorityStyle: priorityStyle)
    }

    static func original(for profile: Profile) -> ScenarioDraft {
        ScenarioDraft(retirementAge: profile.retirementAge, fixedRate: profile.currentEmployeeRate * 100)
    }
}

// MARK: - Retirement comparison

/// A compared scenario shown on the Explore chart with the plan's Current and Adaptive lines.
struct ScenarioOverlay {
    /// The calculated scenario; nil while the first one is on its way, or when it couldn't be
    /// calculated (see `note`).
    let evaluation: API.Evaluation?
    /// The scenario sent (or the saved preset's, or the one on the controls).
    let scenario: API.Scenario?
    /// A newer scenario is being calculated; this one is drawn faintly until it arrives.
    var isUpdating = false
    /// Why there's no line for the controls' scenario, e.g. no live server. Shown at the chart
    /// so a change never silently leaves the plan's lines on screen.
    var note: String? = nil

    /// Matches the server's history labels: "Retire at 69 · adaptive contribution".
    var label: String {
        let age = scenario?.retirementAge ?? evaluation?.projections.custom?.retirementAge
        let contribution = scenario?.employeeContributionRate.map { rate -> String in
            let percent = rate * 100
            return (percent.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(percent))%" : String(format: "%.1f%%", percent))
                + " fixed contribution"
        } ?? "adaptive contribution"
        let base = age.map { "Retire at \($0) · \(contribution)" } ?? contribution
        let debt = scenario?.extraMonthlyDebtCents.map { " · \(Money.whole($0))/mo extra debt" } ?? ""
        let style = scenario?.priorityStyle.map { " · \($0.label) override" } ?? ""
        return base + debt + style
    }
}

/// "Retirement accounts": Current vs Adaptive from the plan's calculation, plus the compared
/// scenario when there is one, on a shared calendar axis.
struct RetirementComparisonSection: View {
    let profile: Profile
    var scenario: ScenarioOverlay? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Retirement accounts")
                .font(.geist(20, .medium, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(profile.evaluation == nil ? "Illustrative preview · not a calculated result"
                                           : "Projected balance · nominal, illustrative assumptions")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)

            HStack(spacing: 20) {
                LegendItem(title: "Current", color: Palette.blue, dashed: true, weight: .regular)
                LegendItem(title: "Adaptive", color: Palette.accent, dashed: false, weight: .medium)
                if scenario != nil {
                    LegendItem(title: "Your scenario", color: Palette.textPrimary, dashed: false, weight: .medium)
                        .opacity(scenarioLine == nil || scenario?.isUpdating == true ? 0.45 : 1)
                        .transition(.opacity)
                }
            }
            .frame(height: 28)
            .padding(.top, 15)

            if let scenario {
                HStack(spacing: 6) {
                    if scenario.isUpdating {
                        ProgressView().controlSize(.mini).tint(Palette.textCaption)
                    }
                    if scenario.note != nil {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(scenarioCaption(scenario))
                        .font(.geist(12, .regular, relativeTo: .caption))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }

            comparisonChart
                .frame(height: 205)

            HStack {
                axisLabel("\(ExploreTimeline.startYear)")
                Spacer()
                axisLabel("\(ExploreTimeline.startYear + span / 2)")
                Spacer()
                (Text(verbatim: String(ExploreTimeline.startYear + span)).font(.geist(12, .medium, relativeTo: .caption))
                 + Text(" · Age ").font(.geist(12, .regular, relativeTo: .caption))
                 + Text("\(profile.age + span)").font(.geist(12, .medium, relativeTo: .caption)))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minHeight: 26)
            .accessibilityElement(children: .combine)
        }
        .animation(Motion.reveal, value: scenario?.evaluation?.inputHash)
        .animation(Motion.reveal, value: scenario?.isUpdating)
    }

    /// The scenario's yearly balances, or nil when it has none to draw (not fundable).
    private var scenarioLine: [Int64]? {
        guard let custom = scenario?.evaluation?.projections.custom, custom.feasible else { return nil }
        let values = custom.yearlyRetirementBalances(years: custom.retirementAge - profile.age)
        return values.count > 1 ? values : nil
    }

    /// Years on the axis: the plan's horizon, extended when the scenario retires later.
    private var span: Int {
        max(profile.yearsToRetirement, (scenarioLine?.count ?? 0) - 1)
    }

    private func scenarioCaption(_ scenario: ScenarioOverlay) -> String {
        if scenario.isUpdating { return "Calculating · \(scenario.label)" }
        if let note = scenario.note { return "\(scenario.label) · \(note)" }
        if scenarioLine == nil { return "\(scenario.label) · not fundable as entered" }
        return scenario.label
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.geist(12, .medium, relativeTo: .caption))
            .foregroundStyle(Palette.textCaption)
    }

    /// The engine's yearly balances on a shared year axis, or the schematic preview.
    @ViewBuilder
    private var comparisonChart: some View {
        if let projections = profile.evaluation?.projections {
            let years = profile.yearsToRetirement
            let adaptive = projections.adaptive.yearlyRetirementBalances(years: years)
            let current = projections.current.yearlyRetirementBalances(years: years)
            if adaptive.count > 1, current.count > 1 {
                YearlyComparisonChart(series: [
                    YearlySeries(name: "Current", values: current.map(Double.init), style: .baseline),
                    YearlySeries(name: "Adaptive", values: adaptive.map(Double.init), style: .primary)
                ] + (scenarioLine.map { [YearlySeries(name: "Your scenario", values: $0.map(Double.init),
                                                      style: .scenario, dimmed: scenario?.isUpdating == true)] } ?? []))
            } else {
                ComparisonChart()
            }
        } else {
            ComparisonChart()
        }
    }
}

private struct LegendItem: View {
    let title: String
    let color: Color
    let dashed: Bool
    let weight: GeistWeight

    var body: some View {
        HStack(spacing: 7) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addLine(to: CGPoint(x: 17, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
            .frame(width: 17, height: 2)
            Text(title)
                .font(.geist(13, weight, relativeTo: .footnote))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(dashed ? "dashed" : "solid") line")
    }
}

// MARK: - Scenario controls

struct ScenarioControls: View {
    @EnvironmentObject private var store: AppStore
    let profile: Profile
    @Binding var draft: ScenarioDraft
    /// Engine result for the compared draft (live, or an exact saved preset).
    @Binding var result: API.Evaluation?
    /// The scenario behind `result` (the one sent, or the saved preset's), so Scenario history
    /// can save that result's inputs.
    var resultScenario: Binding<API.Scenario?> = .constant(nil)
    /// True from the first edit until the recalculated result (or an error) arrives.
    var isUpdating: Binding<Bool> = .constant(false)
    /// Why the controls' scenario has no result (no live server, or the server failed), for the chart.
    var unavailableNote: Binding<String?> = .constant(nil)
    @State private var comparedDraft: ScenarioDraft?
    @State private var status: String?
    @State private var failed = false
    /// The pinned base decision expired; compare again only after a live plan refresh.
    @State private var needsBaseRefresh = false
    @State private var compareTask: Task<Void, Never>?

    /// Wait for the steppers to settle before asking the server, so a run of taps sends one request.
    private static let settleDelay: Duration = .milliseconds(600)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Retirement age: current age + 1 through 80, matching backend validation.
            HStack {
                Text("Retirement age")
                    .font(.geist(17, .medium, relativeTo: .body))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                WordRoll(text: "\(draft.retirementAge)")
                    .font(.numeral(18, .medium, relativeTo: .body))
                    .foregroundStyle(Palette.textPrimary)
                Stepper("Retirement age", value: ageBinding, in: (profile.age + 1)...80)
                    .labelsHidden()
                    .fixedSize()
                    .padding(.leading, Space.m)
            }
            .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: Space.m) {
                Text("Employee contribution")
                    .font(.geist(17, .medium, relativeTo: .body))
                    .foregroundStyle(Palette.textPrimary)
                Picker("Employee contribution", selection: policyBinding) {
                    ForEach(ScenarioDraft.Policy.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 14)

            Group {
                if draft.policy == .adaptive {
                    (Text("Starts at ")
                     + Text(percent(profile.adaptiveEmployeeRate * 100)).font(.geist(13, .medium, relativeTo: .footnote))
                     + Text(" and adjusts as your priorities change."))
                } else {
                    Text("A fixed employee rate for every month, subject to plan limits.")
                }
            }
            .font(.geist(13, .regular, relativeTo: .footnote))
            .foregroundStyle(Palette.textSecondary)
            .lineSpacing(3)
            .padding(.top, 11)

            if draft.policy == .fixed {
                HStack {
                    Text("Fixed rate")
                        .font(.geist(15, .regular, relativeTo: .callout))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(percent(draft.fixedRate))
                        .font(.numeral(18, .medium, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Stepper("Fixed rate", value: rateBinding, in: 0...20, step: 0.5)
                        .labelsHidden()
                        .fixedSize()
                        .padding(.leading, Space.m)
                }
                .frame(minHeight: 44)
                .padding(.top, Space.s)
                .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text("Extra monthly debt payment")
                    .font(.geist(15, .medium, relativeTo: .callout))
                TextField("Automatic priority", text: Binding(
                    get: { draft.extraDebtDollars },
                    set: { draft.extraDebtDollars = $0; draft.preset = nil }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                Text("An entered budget goes to the highest APR debt first. ARM won't add more.")
                    .font(.geist(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, Space.m)

            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    Text("Priority style")
                        .font(.geist(15, .medium, relativeTo: .callout))
                        .foregroundStyle(Palette.textPrimary)
                    if draft.priorityStyle != nil {
                        Text("User override")
                            .font(.geist(11, .medium, relativeTo: .caption2))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 22)
                            .glassCapsule(tint: Palette.accent, interactive: false)
                    }
                }
                Picker("Priority style", selection: Binding(
                    get: { draft.priorityStyle?.rawValue ?? "same" },
                    set: { draft.priorityStyle = $0 == "same" ? nil : API.PlanningPreference(rawValue: $0); draft.preset = nil }
                )) {
                    Text("Keep plan style").tag("same")
                    Text("Balanced (user override)").tag(API.PlanningPreference.balanced.rawValue)
                    Text("Cash security (user override)").tag(API.PlanningPreference.cashSecurity.rawValue)
                    Text("Debt reduction (user override)").tag(API.PlanningPreference.debtReduction.rawValue)
                }
                .labelsHidden()
                Text(priorityCaption)
                    .font(.geist(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.m)

            if isEdited || failed {
                HStack(spacing: Space.m) {
                    if failed {
                        Button(needsBaseRefresh ? "Refresh plan" : "Try again") {
                            schedule(draft, after: .zero, refreshBase: needsBaseRefresh)
                        }
                            .font(.geist(15, .medium, relativeTo: .callout))
                            .foregroundStyle(Palette.accent)
                            .buttonStyle(PressableStyle())
                            .frame(minHeight: 44)
                    }
                    Spacer(minLength: 0)
                    if isEdited {
                        Button {
                            apply(.original)
                        } label: {
                            Label("Reset to plan", systemImage: "arrow.uturn.backward")
                                .font(.geist(15, .medium, relativeTo: .callout))
                        }
                        .foregroundStyle(Palette.accent)
                        .buttonStyle(PressableStyle())
                        .frame(minHeight: 44)
                    }
                }
                .padding(.top, 14)
                .transition(.opacity)
            }

            if let status {
                Text(status)
                    .font(.geist(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Palette.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s)
                    .transition(.opacity)
            }

            Text("Saved scenarios")
                .font(.geist(21, .medium, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 44, alignment: .leading)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            GlassGroup(spacing: Space.s) {
            HStack(spacing: Space.s) {
                PresetChip(isSelected: draft.preset == .original) {
                    Text("Original plan").font(.geist(12, .medium, relativeTo: .caption))
                } action: { apply(.original) }
                PresetChip(isSelected: draft.preset == .retireLater) {
                    Text("Retire ").font(.geist(12, .medium, relativeTo: .caption))
                        + Text("+2").font(.geist(12, .medium, relativeTo: .caption))
                        + Text(" years").font(.geist(12, .medium, relativeTo: .caption))
                } action: { apply(.retireLater) }
                PresetChip(isSelected: draft.preset == .ratePlusOne) {
                    // The label says what the preset actually is — a fixed rate, which can
                    // be below the current election (Morgan: 6% vs 8%) — never "+1 pt"
                    // implying more saving (REPORT B9).
                    Text("Fixed at \(percent(ratePlusOneRate))")
                        .font(.geist(12, .medium, relativeTo: .caption))
                } action: { apply(.ratePlusOne) }
            }
            }
        }
        .animation(Motion.reveal, value: draft.policy)
        .animation(Motion.reveal, value: comparedDraft)
        .sensoryFeedback(.selection, trigger: draft)
        .sensoryFeedback(trigger: result?.inputHash) { _, new in new != nil ? .impact(weight: .medium) : nil }
        .onChange(of: draft) { _, new in
            guard new.requestShape != comparedDraft?.requestShape else { return }
            if new.requestShape == ScenarioDraft.original(for: profile).requestShape {
                // Back to the plan: the chart's own lines already show it.
                clear()
                return
            }
            // Presets resolve instantly (saved or live); stepper edits wait to settle.
            schedule(new, after: new.preset == nil ? Self.settleDelay : .zero)
        }
        .onAppear {
            if isEdited && comparedDraft?.requestShape != draft.requestShape {
                schedule(draft, after: .zero)
            }
        }
        .animation(Motion.reveal, value: isEdited)
        .animation(Motion.reveal, value: failed)
        .animation(Motion.reveal, value: needsBaseRefresh)
        .animation(Motion.reveal, value: draft.priorityStyle)
        // No cancel on disappear: switching tabs mid-calculation used to leave nothing on
        // return (REPORT A7). The request finishes and the result is there when you come back.
    }

    private var isEdited: Bool {
        draft.requestShape != ScenarioDraft.original(for: profile).requestShape
    }

    private var priorityCaption: String {
        if let style = draft.priorityStyle {
            return "This scenario uses \(style.label) instead of the saved plan style. Fund, fees, and return assumptions stay the same."
        }
        return "Keep the saved plan's cash-priority order."
    }

    /// Drops any scenario: the draft is the plan again.
    private func clear() {
        compareTask?.cancel()
        compareTask = nil
        comparedDraft = nil
        status = nil
        failed = false
        needsBaseRefresh = false
        result = nil
        unavailableNote.wrappedValue = nil
        isUpdating.wrappedValue = false
    }

    /// Recalculates `compared` after `delay`, replacing any pending or in-flight request. The
    /// previous result stays on screen, marked as updating, until the new one arrives.
    private func schedule(_ compared: ScenarioDraft, after delay: Duration, refreshBase: Bool = false) {
        compareTask?.cancel()
        comparedDraft = compared
        failed = false
        needsBaseRefresh = false
        unavailableNote.wrappedValue = nil
        isUpdating.wrappedValue = true
        compareTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await compare(compared, refreshBaseFirst: refreshBase)
            guard !Task.isCancelled, comparedDraft?.requestShape == compared.requestShape else { return }
            compareTask = nil
            isUpdating.wrappedValue = false
        }
    }

    /// Exact saved preset when offline; otherwise a live `/v1/evaluate` with the draft as scenario.
    private func compare(_ compared: ScenarioDraft, refreshBaseFirst: Bool = false) async {
        if !compared.extraDebtDollars.isEmpty &&
            (Double(compared.extraDebtDollars) == nil || (Double(compared.extraDebtDollars) ?? 0) < 0) {
            status = "Enter a nonnegative dollar amount for extra debt payment."
            failed = true
            unavailableNote.wrappedValue = "invalid debt budget"
            return
        }
        func current() -> Bool { !Task.isCancelled && comparedDraft?.requestShape == compared.requestShape }
        func show(saved preset: DemoPreset, _ message: String) -> Bool {
            guard let saved = store.savedEvaluation(for: profile.id, preset: preset) else { return false }
            result = saved.evaluation
            resultScenario.wrappedValue = store.savedArtifact(for: profile.id, preset: preset)?.scenario
            status = message
            return true
        }
        if !store.isLiveEnabled {
            if let preset = compared.preset?.demoPreset, show(saved: preset, "Saved calculation for this preset.") { return }
            result = nil
            unavailableNote.wrappedValue = "needs the live server to calculate"
            status = "No live server is set, so only the saved presets below can be shown. Add the server's address in Modeling assumptions to calculate your own scenario."
            return
        }
        let scenario = compared.apiScenario
        do {
            if refreshBaseFirst {
                status = "Refreshing the plan, then comparing…"
                try await store.refreshLiveBase()
                guard current() else { return }
            }
            let loaded = try await store.evaluateScenario(scenario)
            guard current() else { return }
            result = loaded.evaluation
            resultScenario.wrappedValue = scenario
            status = loaded.evaluation.projections.custom?.feasible == false
                ? "This scenario can't be funded as entered. See the outcomes below."
                : refreshBaseFirst
                    ? "Live calculation · the plan was refreshed first."
                    : "Live calculation · updates as you change the controls."
        } catch {
            guard current() else { return }
            if (error as? APIError) == .cancelled { return }
            // A stale pin is recoverable: refresh the live plan once, then retry.
            if !refreshBaseFirst, (error as? APIError)?.isStaleBaseDecision == true {
                status = "The plan on the server changed. Refreshing, then comparing…"
                do {
                    try await store.refreshLiveBase()
                    guard current() else { return }
                    let loaded = try await store.evaluateScenario(scenario)
                    guard current() else { return }
                    result = loaded.evaluation
                    resultScenario.wrappedValue = scenario
                    status = loaded.evaluation.projections.custom?.feasible == false
                        ? "This scenario can't be funded as entered. See the outcomes below."
                        : "Live calculation · the plan was refreshed first."
                    return
                } catch {
                    guard current() else { return }
                    if (error as? APIError) == .cancelled { return }
                    result = nil
                    failed = true
                    needsBaseRefresh = true
                    unavailableNote.wrappedValue = "plan needs a refresh"
                    status = "Refresh the plan, then compare again. The previous comparison is no longer valid."
                    return
                }
            }
            // A transport failure shouldn't hide a saved preset the draft matches:
            // show it and say so, instead of an error that suggests retrying (A3).
            if Self.isTransport(error), let preset = compared.preset?.demoPreset,
               show(saved: preset, "Offline. Showing the saved calculation for this preset.") { return }
            // The old line no longer matches the controls, so it goes.
            result = nil
            failed = true
            needsBaseRefresh = (error as? APIError)?.isStaleBaseDecision == true
            unavailableNote.wrappedValue = needsBaseRefresh
                ? "plan needs a refresh"
                : Self.isTransport(error) ? "couldn't reach the server" : "couldn't be calculated"
            status = needsBaseRefresh
                ? "Refresh the plan, then compare again. The previous comparison is no longer valid."
                : Self.message(for: error)
        }
    }

    /// Failures where no server answer exists, so a matching saved preset is the better
    /// result (A3). A `.server` envelope is a real answer (e.g. infeasible) and is shown.
    private static func isTransport(_ error: Error) -> Bool {
        switch error as? APIError {
        case .unreachable, .timedOut, .invalidBaseURL, .unexpectedStatus, .invalidResponse: return true
        default: return false
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? APIError {
        case .server(_, let body): return body.message
        case .timedOut: return "The calculation took too long. Try again."
        case .unreachable, .invalidBaseURL: return "Reconnect for a custom scenario. Saved presets still work offline."
        case .unexpectedStatus(let status):
            return "The server answered with an error (\(status)). Check that the backend is running."
        case .invalidResponse:
            return "The server's answer didn't match what the app expects. Check that the backend is up to date."
        default: return "Couldn't calculate this scenario."
        }
    }

    // Manual edits clear the preset highlight.
    private var ageBinding: Binding<Int> {
        Binding { draft.retirementAge } set: { draft.retirementAge = $0; draft.preset = nil }
    }

    private var policyBinding: Binding<ScenarioDraft.Policy> {
        Binding { draft.policy } set: { draft.policy = $0; draft.preset = nil }
    }

    private var rateBinding: Binding<Double> {
        Binding { draft.fixedRate } set: { draft.fixedRate = $0; draft.preset = nil }
    }

    /// Matches export_demo.py: the opening Adaptive rate plus one point, held fixed.
    private var ratePlusOneRate: Double {
        min(((profile.adaptiveEmployeeRate * 100 + 1) * 2).rounded() / 2, 20)
    }

    private func apply(_ preset: ScenarioDraft.Preset) {
        var next = ScenarioDraft.original(for: profile)
        switch preset {
        case .original: break
        case .retireLater: next.retirementAge = min(profile.retirementAge + 2, 80)
        case .ratePlusOne:
            next.policy = .fixed
            next.fixedRate = ratePlusOneRate
        }
        next.preset = preset
        draft = next
    }

    private func percent(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))%" : String(format: "%.1f%%", value)
    }
}

private struct PresetChip<Label: View>: View {
    let isSelected: Bool
    @ViewBuilder var label: Label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                // Non-interactive glass: interactive glass on a button label swallows the tap.
                .glassCapsule(tint: isSelected ? Palette.accent : nil, interactive: false)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(Motion.select, value: isSelected)
    }
}

// MARK: - Whole-picture outcomes

struct OutcomeRows: View {
    /// Saved or live evaluation for the plan on screen.
    let evaluation: API.Evaluation?
    /// Result of "Compare scenario", whose `custom` projection joins the comparison.
    var custom: API.Evaluation? = nil
    @State private var expanded: Set<String> = []

    private struct Row { let title: String; let lines: [(String, String)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Compare the whole picture")
                .font(.geist(21, .medium, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text("Retirement balance is only part of the result. Compare debt interest, payoff timing, and emergency cash alongside it.")
                .font(.geist(15, .regular, relativeTo: .callout))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 17)

            ForEach(rows, id: \.title) { row in
                let isOpen = expanded.contains(row.title)
                Button {
                    withAnimation(Motion.reveal) {
                        if isOpen { expanded.remove(row.title) } else { expanded.insert(row.title) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.m) {
                            Text(row.title)
                                .font(.geist(15, .regular, relativeTo: .callout))
                                .foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.textCaption)
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                        }
                        .frame(minHeight: 44)
                        if isOpen {
                            VStack(alignment: .leading, spacing: 4) {
                                if row.lines.isEmpty {
                                    Text("Shown after a live calculation.")
                                        .font(.geist(12, .regular, relativeTo: .caption))
                                        .foregroundStyle(Palette.textCaption)
                                } else {
                                    ForEach(row.lines, id: \.0) { line in
                                        HStack {
                                            Text(line.0)
                                                .font(.geist(13, .regular, relativeTo: .footnote))
                                                .foregroundStyle(Palette.textSecondary)
                                            Spacer()
                                            Text(line.1)
                                                .font(.numeral(13, .medium, relativeTo: .footnote))
                                                .monospacedDigit()
                                                .foregroundStyle(Palette.textPrimary)
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                            .padding(.bottom, Space.s)
                            .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(PressableStyle(scale: 1, dim: 0.7))
            }

            Text(evaluation == nil
                 ? "Values appear after calculation. Preview curves show the intended comparison layout only."
                 : "Nominal values from the plan calculation, using the illustrative assumptions.")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .sensoryFeedback(.selection, trigger: expanded)
        // The first scenario result opens the balance row, so the comparison is visible
        // without hunting for it.
        .onChange(of: custom?.inputHash) { old, new in
            if old == nil, new != nil { withAnimation(Motion.reveal) { _ = expanded.insert("Retirement-account balance") } }
        }
    }

    /// Current, Adaptive and (when compared) the custom scenario, straight from the response.
    private var strategies: [(String, API.Projection)] {
        // The scenario response carries the plan's Current and Adaptive too, so rows still
        // fill in if the base plan failed to load but the scenario succeeded (REPORT A7).
        guard let evaluation = evaluation ?? custom else { return [] }
        var list = [("Current", evaluation.projections.current), ("Adaptive", evaluation.projections.adaptive)]
        if let scenario = custom?.projections.custom { list.append(("Your scenario", scenario)) }
        return list
    }

    private var rows: [Row] {
        let s = strategies
        func line(_ name: String, _ p: API.Projection, _ value: (API.Projection) -> String) -> (String, String) {
            (name, p.feasible ? value(p) : "Not fundable")
        }
        return [
            Row(title: "Retirement-account balance", lines: s.map { name, p in
                line(name, p) { Self.money($0.retirementBalanceNominalCents) }
            }),
            Row(title: "In today's dollars", lines: s.map { name, p in
                line(name, p) { Self.money($0.retirementBalanceTodayCents) }
            }),
            Row(title: "Debt-free", lines: s.map { name, p in
                line(name, p) { Self.debtFree($0.debtFreeMonth) }
            }),
            Row(title: "Total debt interest", lines: s.map { name, p in
                line(name, p) { Self.money($0.cumulativeDebtInterestCents) }
            }),
            Row(title: "Emergency-reserve milestones", lines: s.map { name, p in
                line(name, p) { "Starter \(Self.month($0.starterReserveMonth)) · Full \(Self.month($0.fullReserveMonth))" }
            }),
            Row(title: "Cash & debt at retirement", lines: s.map { name, p in
                line(name, p) { "\(Self.money($0.cashNominalCents)) · \(Self.money($0.debtNominalCents))" }
            })
        ]
    }

    private static func money(_ cents: Int64?) -> String { cents.map(Money.whole) ?? "—" }

    /// Month 0 is today; later months become a calendar label ("Jan 2028").
    private static func month(_ month: Int?) -> String {
        guard let month else { return "—" }
        return month == 0 ? "Now" : ExploreTimeline.label(forMonth: month)
    }

    private static func debtFree(_ month: Int?) -> String {
        guard let month else { return "Not paid off before retirement" }
        return month == 0 ? "Now" : ExploreTimeline.label(forMonth: month)
    }
}
