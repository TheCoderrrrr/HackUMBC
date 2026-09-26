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
    }

    var retirementAge: Int
    var policy: Policy = .adaptive
    /// Employee rate in percent, 0…20 in 0.5 steps, used when `policy == .fixed`.
    var fixedRate: Double
    var preset: Preset? = .original

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
            Text("Illustrative preview · not a calculated result")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 2)

            HStack(spacing: 20) {
                LegendItem(title: "Current", color: Palette.peach, dashed: true, weight: .regular)
                LegendItem(title: "Adaptive", color: Palette.lavender, dashed: false, weight: .medium)
            }
            .frame(height: 28)
            .padding(.top, 15)

            ComparisonChart()
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
    let profile: Profile
    @Binding var draft: ScenarioDraft
    @State private var comparedDraft: ScenarioDraft?

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

            Button { comparedDraft = draft } label: {
                Label("Compare scenario", systemImage: "square.split.2x1")
            }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 22)

            if let comparedDraft {
                Text(comparedDraft == .original(for: profile)
                     ? "This is the saved plan. The chart already shows it."
                     : "Custom comparisons need a live calculation. The chart keeps the saved Current and Adaptive preview.")
                    .font(.geist(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Palette.textCaption)
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
        .onChange(of: draft) { _, new in
            if new != comparedDraft { comparedDraft = nil }
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
        // The exact +1-point rate comes from the engine artifact; the draft only
        // records the preset until a live calculation is available.
        case .ratePlusOne: break
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
                .foregroundStyle(isSelected ? Palette.lavender : Palette.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .glassCapsule(tint: isSelected ? Palette.lavender : nil)
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
    @State private var expanded: Set<String> = []

    private let outcomes = [
        "Retirement-account balance",
        "Debt-free timing & total interest",
        "Emergency-reserve milestones",
        "Cash & debt at retirement"
    ]
    private let symbols = [
        "Retirement-account balance": "building.columns.fill",
        "Debt-free timing & total interest": "creditcard.fill",
        "Emergency-reserve milestones": "umbrella.fill",
        "Cash & debt at retirement": "banknote.fill"
    ]

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

            ForEach(outcomes, id: \.self) { outcome in
                let isOpen = expanded.contains(outcome)
                Button {
                    withAnimation(Motion.reveal) {
                        if isOpen { expanded.remove(outcome) } else { expanded.insert(outcome) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.m) {
                            IconBadge(systemName: symbols[outcome] ?? "circle", size: 28)
                            Text(outcome)
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
                            Text("Shown after a live calculation.")
                                .font(.geist(12, .regular, relativeTo: .caption))
                                .foregroundStyle(Palette.textCaption)
                                .padding(.leading, 40)
                                .padding(.bottom, Space.s)
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(PressableStyle(scale: 1, dim: 0.7))
                .accessibilityValue(isOpen ? "Shown after a live calculation" : "")
            }

            Text("Values appear after calculation. Preview curves show the intended comparison layout only.")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }
}
