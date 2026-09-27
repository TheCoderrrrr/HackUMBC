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
    var preset: Preset? = .original

    /// The fields that change the request; `preset` is only a chip highlight, so editing a
    /// control and reverting it no longer sends an identical request (REPORT E2).
    var requestShape: RequestShape { RequestShape(age: retirementAge, policy: policy, rate: fixedRate) }

    struct RequestShape: Equatable {
        let age: Int
        let policy: Policy
        let rate: Double
    }

    static func original(for profile: Profile) -> ScenarioDraft {
        ScenarioDraft(retirementAge: profile.retirementAge, fixedRate: profile.currentEmployeeRate * 100)
    }
}

// MARK: - Retirement comparison

/// "Retirement accounts": legend, schematic Current vs Adaptive chart, shared calendar axis.
struct RetirementComparisonSection: View {
    let profile: Profile

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
            }
            .frame(height: 28)
            .padding(.top, 15)

            comparisonChart
                .frame(height: 205)

            HStack {
                axisLabel("\(ExploreTimeline.startYear)")
                Spacer()
                axisLabel("\(ExploreTimeline.startYear + profile.yearsToRetirement / 2)")
                Spacer()
                (Text(verbatim: String(ExploreTimeline.startYear + profile.yearsToRetirement)).font(.geist(12, .medium, relativeTo: .caption))
                 + Text(" · Age ").font(.geist(12, .regular, relativeTo: .caption))
                 + Text("\(profile.retirementAge)").font(.geist(12, .medium, relativeTo: .caption)))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minHeight: 26)
            .accessibilityElement(children: .combine)
        }
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.geist(12, .medium, relativeTo: .caption))
            .foregroundStyle(Palette.textCaption)
    }

    /// The engine's Current and Adaptive yearly balances on a shared scale, or the schematic preview.
    @ViewBuilder
    private var comparisonChart: some View {
        if let projections = profile.evaluation?.projections {
            let years = profile.yearsToRetirement
            let adaptive = projections.adaptive.yearlyRetirementBalances(years: years)
            let current = projections.current.yearlyRetirementBalances(years: years)
            let top = Double(max(adaptive.max() ?? 1, current.max() ?? 1, 1))
            if adaptive.count > 1, current.count > 1 {
                ComparisonChart(adaptive: adaptive.map { Double($0) / top },
                                current: current.map { Double($0) / top })
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
    @State private var comparedDraft: ScenarioDraft?
    @State private var status: String?
    @State private var compareTask: Task<Void, Never>?

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

            Button(action: compare) {
                HStack(spacing: Space.s) {
                    if compareTask != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.split.2x1")
                    }
                    Text("Compare scenario")
                }
            }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(compareTask != nil)
                .padding(.top, 22)

            if comparedDraft != nil, let status {
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
                    Text("Rate ").font(.geist(12, .medium, relativeTo: .caption))
                        + Text("+1").font(.geist(12, .medium, relativeTo: .caption))
                        + Text(" pt").font(.geist(12, .medium, relativeTo: .caption))
                } action: { apply(.ratePlusOne) }
            }
            }
        }
        .animation(Motion.reveal, value: draft.policy)
        .animation(Motion.reveal, value: comparedDraft)
        .sensoryFeedback(.selection, trigger: draft)
        .sensoryFeedback(trigger: comparedDraft) { _, new in new != nil ? .impact(weight: .medium) : nil }
        .onChange(of: draft) { _, new in
            if new.requestShape != comparedDraft?.requestShape {
                compareTask?.cancel()
                compareTask = nil
                comparedDraft = nil
                status = nil
                result = nil
            }
        }
        .onDisappear { compareTask?.cancel() }
    }

    /// Exact saved preset when offline; otherwise a live `/v1/evaluate` with the draft as scenario.
    private func compare() {
        let compared = draft
        comparedDraft = compared
        result = nil
        guard compared.requestShape != ScenarioDraft.original(for: profile).requestShape else {
            status = "This is the saved plan. The chart already shows it."
            return
        }
        if !store.isLiveEnabled {
            if let preset = compared.preset?.demoPreset,
               let saved = store.savedEvaluation(for: profile.id, preset: preset) {
                result = saved.evaluation
                status = "Saved calculation for this preset."
            } else {
                status = "Reconnect for a custom scenario. Saved presets still work offline."
            }
            return
        }
        status = nil
        let scenario = API.Scenario(retirementAge: compared.retirementAge,
                                    employeeContributionRate: compared.policy == .fixed ? compared.fixedRate / 100 : nil)
        compareTask = Task {
            defer { if comparedDraft?.requestShape == compared.requestShape { compareTask = nil } }
            do {
                let loaded = try await store.evaluateScenario(scenario)
                guard !Task.isCancelled, comparedDraft?.requestShape == compared.requestShape else { return }
                result = loaded.evaluation
                status = loaded.evaluation.projections.custom?.feasible == false
                    ? "This scenario can't be funded as entered. See the outcomes below."
                    : "Live calculation for this scenario."
            } catch {
                guard !Task.isCancelled, comparedDraft?.requestShape == compared.requestShape else { return }
                // A transport failure shouldn't hide a saved preset the draft matches:
                // show it and say so, instead of an error that suggests retrying (A3).
                if Self.isTransport(error),
                   let preset = compared.preset?.demoPreset,
                   let saved = store.savedEvaluation(for: profile.id, preset: preset) {
                    result = saved.evaluation
                    status = "Offline. Showing the saved calculation for this preset."
                } else {
                    status = Self.message(for: error)
                }
            }
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

    private func apply(_ preset: ScenarioDraft.Preset) {
        var next = ScenarioDraft.original(for: profile)
        switch preset {
        case .original: break
        case .retireLater: next.retirementAge = min(profile.retirementAge + 2, 80)
        // Matches export_demo.py: the opening Adaptive rate plus one point, held fixed.
        case .ratePlusOne:
            next.policy = .fixed
            next.fixedRate = min(((profile.adaptiveEmployeeRate * 100 + 1) * 2).rounded() / 2, 20)
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
    }

    /// Current, Adaptive and (when compared) the custom scenario, straight from the response.
    private var strategies: [(String, API.Projection)] {
        guard let evaluation else { return [] }
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
            Row(title: "Debt-free timing & total interest", lines: s.map { name, p in
                line(name, p) { "\(Self.month($0.debtFreeMonth)) · \(Self.money($0.cumulativeDebtInterestCents))" }
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
}
