import SwiftUI

/// Fund assumptions and the AI-versus-default-rules comparison for the evaluation
/// currently on screen — the saved plan, or a compared Explore scenario.
struct FundAndRulesSection: View {
    let evaluation: API.Evaluation?
    /// The scenario that produced `evaluation`, when this is a custom comparison.
    var scenario: API.Scenario? = nil
    var title: String = "What drives this plan"

    @State private var showRules = false
    @State private var showGlidePath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.geist(21, .medium, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if let fund = evaluation?.assumptions.fundModel {
                fundSummary(fund)
            } else if evaluation != nil {
                Text("No target-date fund is selected. Projections use a generic retirement-age glide path.")
                    .font(.geist(15, .regular, relativeTo: .callout))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else {
                Text("Fund and fee assumptions appear after a live or saved calculation.")
                    .font(.geist(15, .regular, relativeTo: .callout))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if let style = scenario?.priorityStyle {
                HStack(spacing: Space.s) {
                    Text("User override")
                        .font(.geist(11, .medium, relativeTo: .caption2))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .glassCapsule(tint: Palette.accent, interactive: false)
                    Text("Priority style is \(style.label), not the saved plan style.")
                        .font(.geist(13, .regular, relativeTo: .footnote))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.m)
                .accessibilityElement(children: .combine)
            }

            if let comparison = evaluation?.rulesComparison {
                rulesComparison(comparison, in: evaluation!)
                    .padding(.top, Space.l)
            }
        }
        .animation(Motion.reveal, value: evaluation?.inputHash)
        .animation(Motion.reveal, value: showRules)
        .animation(Motion.reveal, value: showGlidePath)
    }

    @ViewBuilder
    private func fundSummary(_ fund: API.FundModel) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(fund.fundName) · target \(fund.targetYear) · modeled fee \(FundCopy.fee(fund.appliedExpenseRatio)).")
                .font(.geist(16, .regular, relativeTo: .body))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(fund.glidePathMode == "documented"
                 ? "The issuer's documented glide path sets the modeled stock mix."
                 : "A generic glide path is used because numeric issuer anchors are unavailable.")
                .font(.geist(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let limitation = fund.limitation, !limitation.isEmpty {
                Text(limitation)
                    .font(.geist(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.l) {
                if let url = URL(string: fund.glidePathSourceURL) {
                    Link("Glide path source", destination: url)
                }
                if let url = URL(string: fund.feeSourceURL) {
                    Link("Fee source", destination: url)
                }
            }
            .font(.geist(14, .medium, relativeTo: .subheadline))
            .foregroundStyle(Palette.accent)
            .padding(.top, 2)

            Text("Catalog \(fund.catalogVersion) · \(fund.shareClassID) · fee facts as of \(FundCopy.asOf(fund.feeAsOfDate))")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .fixedSize(horizontal: false, vertical: true)

            if !fund.glidePath.isEmpty {
                disclosure(title: "Modeled stock mix", isOpen: $showGlidePath) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(fund.glidePath.enumerated()), id: \.offset) { _, anchor in
                            HStack {
                                Text(Self.yearsLabel(anchor.yearsToRetirement))
                                    .font(.geist(13, .regular, relativeTo: .footnote))
                                    .foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Text("\(FundCopy.pct1(anchor.equityWeight)) stocks")
                                    .font(.numeral(13, .medium, relativeTo: .footnote))
                                    .foregroundStyle(Palette.textPrimary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("Equity weight by years to the fund's target date. Fees are deducted from illustrative asset-class returns.")
                            .font(.geist(12, .regular, relativeTo: .caption))
                            .foregroundStyle(Palette.textCaption)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func rulesComparison(_ comparison: API.RulesComparison, in evaluation: API.Evaluation) -> some View {
        disclosure(title: Self.rulesTitle(for: comparison), isOpen: $showRules) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(Self.decisionLine(comparison, evaluation: evaluation))
                    .font(.geist(14, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.outcomeLine(comparison))
                    .font(.geist(14, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let ai = comparison.aiRetirementBalanceCents, let rules = comparison.rulesRetirementBalanceCents {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comparison.basis == "custom" ? "This scenario" : "This plan")
                                .font(.geist(13, .regular, relativeTo: .footnote))
                                .foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text(Money.whole(ai))
                                .font(.numeral(13, .medium, relativeTo: .footnote))
                                .foregroundStyle(Palette.textPrimary)
                        }
                        HStack {
                            Text("Default rules")
                                .font(.geist(13, .regular, relativeTo: .footnote))
                                .foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text(Money.whole(rules))
                                .font(.numeral(13, .medium, relativeTo: .footnote))
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Text("The comparison changes the decision order only. Fund, cash flow, and return assumptions stay fixed.")
                    .font(.geist(12, .regular, relativeTo: .caption))
                    .foregroundStyle(Palette.textCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func disclosure<Content: View>(title: String, isOpen: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isOpen.wrappedValue.toggle()
            } label: {
                HStack(spacing: Space.m) {
                    Text(title)
                        .font(.geist(15, .medium, relativeTo: .callout))
                        .foregroundStyle(Palette.accent)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textCaption)
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 1, dim: 0.7))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isOpen.wrappedValue ? "Collapses this section." : "Expands this section.")

            if isOpen.wrappedValue {
                content()
                    .padding(.bottom, Space.s)
                    .transition(.opacity)
            }
        }
    }

    private static func yearsLabel(_ years: Double) -> String {
        years == 0 ? "At target year" : "\(years.formatted(.number.precision(.fractionLength(0...1)))) years to target"
    }

    private static func rulesTitle(for comparison: API.RulesComparison) -> String {
        comparison.basis == "custom"
            ? "Scenario compared with default rules"
            : "AI decision compared with default rules"
    }

    private static func decisionLine(_ comparison: API.RulesComparison, evaluation: API.Evaluation) -> String {
        let chose = evaluation.decisionSummary.source == .ai ? "AI chose" : "Default rules chose"
        let ai = comparison.aiPriorities.map(\.label).joined(separator: " → ")
        let rules = comparison.rulesPriorities.map(\.label).joined(separator: " → ")
        return "\(chose) \(ai). Default rules choose \(rules)."
    }

    private static func outcomeLine(_ comparison: API.RulesComparison) -> String {
        if comparison.outcome == "unavailable" || comparison.differenceCents == nil {
            return "The projected outcome could not be compared."
        }
        if comparison.outcome == "equal" || comparison.differenceCents == 0 {
            return "The projected retirement balance is the same."
        }
        let amount = Money.whole(abs(comparison.differenceCents ?? 0))
        return "The projected retirement balance is \(amount) \(comparison.outcome) than default rules."
    }
}
