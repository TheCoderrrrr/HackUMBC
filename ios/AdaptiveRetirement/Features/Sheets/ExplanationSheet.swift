import SwiftUI

/// "Why this plan?" — with a loaded evaluation, everything comes from the response:
/// the decision's priority order, per-priority rationale and tradeoffs, the fallback
/// reason, the explanation's narrative and state summary, and what changed (REPORT B2).
/// The hand-typed `DemoData` copy is only the no-evaluation preview.
struct ExplanationSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let profile = store.displayProfile
        SheetScaffold(title: "Why this plan?") {
            if let evaluation = profile.evaluation {
                ResponseExplanation(profile: profile, evaluation: evaluation)
            } else {
                FixtureExplanation(profile: profile)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SheetFooterAction(title: "Got it") {
                store.sheet = nil  // the app's sheet state; dismiss() is a fallback
                dismiss()
            }
        }
    }
}

// MARK: - Response-driven content (a real calculation is loaded)

private struct ResponseExplanation: View {
    let profile: Profile
    let evaluation: API.Evaluation

    private var decision: API.DecisionSummary { evaluation.decisionSummary }
    private var explanation: API.Explanation { evaluation.explanation }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(profile.explanationHeadline)
                .font(.geist(25, .regular, relativeTo: .title2))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 21)

            // The narrative, whichever agent wrote it, with an honest source chip.
            SourceChip(title: explanation.source == .ai ? "AI-written" : "Template")
                .padding(.top, 16)
            EmphasizedText(explanation.narrative, lineSpacing: 3.5)
                .padding(.top, 10)

            SheetSectionTitle("Where you stand")
                .padding(.top, 23)
            EmphasizedText(explanation.stateSummary, lineSpacing: 3.5)
                .padding(.top, 9)

            SheetSectionTitle("Priority order")
                .padding(.top, 25)
            VStack(alignment: .leading, spacing: 23) {
                ForEach(Array(decision.orderedPriorities.enumerated()), id: \.offset) { index, priority in
                    let rationale = decision.rationale.first { $0.priority == priority.rawValue }
                    PriorityStep(number: index + 1, title: priority.title,
                                 detail: rationale?.summary ?? "", tradeoff: rationale?.tradeoff)
                }
            }
            .padding(.top, 15)

            if let reason = decision.fallbackReason {
                Text(Self.fallbackCaption(reason))
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textCaption)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 15)
            }

            if !explanation.changes.isEmpty {
                Hairline(color: Palette.hairlineStrong)
                    .padding(.top, 23)
                SheetSectionTitle("What changed since your last plan")
                    .padding(.top, 19)
                    .padding(.bottom, 8)
                ForEach(explanation.changes, id: \.fieldPath) { change in
                    InputRow(label: Self.changeLabel(change.fieldPath),
                             value: "\(Self.scalarText(change.before, for: change.fieldPath)) → \(Self.scalarText(change.after, for: change.fieldPath))")
                }
            }

            Hairline(color: Palette.hairlineStrong)
                .padding(.top, 23)

            SheetSectionTitle("Supporting inputs")
                .padding(.top, 19)
                .padding(.bottom, 8)
            ForEach(profile.supportingInputs, id: \.label) { input in
                InputRow(label: input.label, value: input.value, unit: input.unit)
            }

            SourceCaption(lines: [profile.origin.rawValue, SheetCopy.source(profile), SheetCopy.asOf])
                .padding(.top, 12)
        }
    }

    /// A readable reason the rules order was used instead of a live AI decision.
    static func fallbackCaption(_ code: String) -> String {
        switch code {
        case "AI_UNAVAILABLE":
            return "Live AI isn't configured on this server, so the standard priority order was used."
        case "TIMEOUT":
            return "The AI timed out, so the standard priority order was used."
        case "RATE_LIMITED":
            return "The AI rate limit was reached, so the standard priority order was used."
        case "AI_COOLDOWN":
            return "AI is paused briefly after repeated timeouts, so the standard priority order was used."
        case "PROVIDER_ERROR":
            return "The AI provider hit an error, so the standard priority order was used."
        case "NO_AI_PROPOSAL":
            return "The AI didn't return a proposal, so the standard priority order was used."
        case "BLOCKED_FINANCIAL_INPUT":
            return "Some inputs block planning, so no AI ordering was needed."
        default:
            if code.hasPrefix("INVALID") || code.hasPrefix("UNSUPPORTED") {
                return "The AI's answer didn't pass validation, so the standard priority order was used."
            }
            return "The standard priority order was used (\(code))."
        }
    }

    static func changeLabel(_ path: String) -> String {
        switch path {
        case "planning_preference": return "Planning preference"
        case "decision.ordered_priorities": return "Priority order"
        case "plan.primary_action_id": return "Primary action"
        case "plan.primary_action.monthly_cash_cost_cents": return "Primary action cost"
        case "employee_contribution_rate": return "Contribution rate"
        case "monthly_living_expenses_cents": return "Living expenses"
        case "emergency_cash_cents": return "Emergency cash"
        case "financial_state.emergency_months": return "Emergency months"
        case "financial_state.high_interest_debt_cents": return "High-interest debt"
        case "financial_state.current_monthly_surplus_cents": return "Monthly surplus"
        default: return path.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func scalarText(_ scalar: API.Scalar, for path: String) -> String {
        switch scalar {
        case .string(let value):
            if path == "plan.primary_action_id" {
                if value == "employee-contribution" { return "Retirement contribution" }
                if value.hasPrefix("debt-") { return "Extra debt payment" }
            }
            if path == "decision.ordered_priorities" {
                return value.split(separator: ",").map { $0.replacingOccurrences(of: "_", with: " ") }
                    .joined(separator: " → ")
            }
            return value.replacingOccurrences(of: "_", with: " ")
        case .int(let cents):
            return path.hasSuffix("_cents") ? Money.whole(cents) : String(cents)
        case .double(let value):
            if path.hasSuffix("_rate") { return SheetCopy.percent(value) }
            if path.hasSuffix("_months") { return SheetCopy.months(value) }
            return value.formatted(.number.precision(.fractionLength(0...2)))
        case .bool(let value): return value ? "Yes" : "No"
        case .null: return "—"
        }
    }
}

/// Small capsule labeling who wrote the narrative.
private struct SourceChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(TypeScale.caption)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassCapsule(interactive: false)
            .accessibilityLabel("Narrative source: \(title)")
    }
}

private extension API.Priority {
    var title: String {
        switch self {
        case .starterReserve: return "Build a starter reserve"
        case .highAprDebt: return "Pay down high-APR debt"
        case .fullReserve: return "Build a full reserve"
        }
    }
}

// MARK: - Fixture preview (no calculation loaded)

private struct FixtureExplanation: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(profile.explanationHeadline)
                .font(.geist(25, .regular, relativeTo: .title2))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 21)

            EmphasizedText(profile.explanationSummary, lineSpacing: 3.5)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 23) {
                ForEach(Array(profile.explanationSteps.enumerated()), id: \.offset) { index, step in
                    PriorityStep(number: index + 1, title: step.title, detail: step.detail)
                }
            }
            .padding(.vertical, 23)

            Hairline(color: Palette.hairlineStrong)

            SheetSectionTitle("The tradeoff")
                .padding(.top, 21)
            EmphasizedText(profile.explanationTradeoff, lineSpacing: 3.5)
                .padding(.top, 9)
                .padding(.bottom, 25)

            Hairline(color: Palette.hairlineStrong)

            SheetSectionTitle("Supporting inputs")
                .padding(.top, 19)
                .padding(.bottom, 8)
            ForEach(profile.supportingInputs, id: \.label) { input in
                InputRow(label: input.label, value: input.value, unit: input.unit)
            }

            SourceCaption(lines: [profile.origin.rawValue, SheetCopy.source(profile), SheetCopy.asOf])
                .padding(.top, 12)
        }
    }
}

// MARK: - Shared pieces

private struct PriorityStep: View {
    let number: Int
    let title: String
    let detail: String
    var tradeoff: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.geist(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.accent)
                .frame(width: 27, height: 27)
                .background(Circle().fill(Palette.raised))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.geist(17, .medium, relativeTo: .headline))
                    .foregroundStyle(Palette.textPrimary)
                if !detail.isEmpty {
                    EmphasizedText(detail, size: 14, style: .subheadline, lineSpacing: 3)
                }
                if let tradeoff, !tradeoff.isEmpty {
                    EmphasizedText("Tradeoff: \(tradeoff)", size: 13, style: .footnote,
                                   color: Palette.textCaption, lineSpacing: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Priority \(number). \(title). \(detail.replacingOccurrences(of: "**", with: ""))")
    }
}

// MARK: - Display copy assembled from fixture values (preview only)

private struct SupportingInput {
    let label: String
    let value: String
    var unit: String? = nil
}

private extension Profile {
    var extraDebtPayment: Int64 { primaryActionAmountCents ?? 0 }
    var remainingCashCents: Int64 {
        cashPriorities.first { $0.kind == .remaining }?.amountCents ?? 0
    }

    var explanationHeadline: String {
        // The engine's primary action drives the headline when a calculation is loaded (B3).
        if let evaluation { return ReasonCopy.headline(for: evaluation) }
        return extraDebtPayment > 0 ? "Keep your match.\nReduce costly debt." : explanation.headline
    }

    var explanationSummary: String {
        if extraDebtPayment > 0, let debt = debts.max(by: { $0.apr < $1.apr }) {
            return "Keep the full employer match, then focus available cash on the **\(SheetCopy.percent(debt.apr))** APR balance."
        }
        return explanation.narrative
    }

    var explanationSteps: [(title: String, detail: String)] {
        let minimums = debts.reduce(Int64(0)) { $0 + $1.minimumCents }
        var steps: [(String, String)] = []

        steps.append(("Protect the essentials", minimums > 0
            ? "**\(Money.whole(monthlyLivingCents))** for living costs and the **\(Money.whole(minimums))** debt minimum come first."
            : "**\(Money.whole(monthlyLivingCents))** for living costs comes first."))

        if matchCaptured {
            steps.append(("Keep the full employer match",
                          "Your **\(SheetCopy.percent(adaptiveEmployeeRate))** contribution adds **\(Money.whole(employeeMonthlyCents))**. Your employer adds another **\(Money.whole(employerMonthlyCents))**."))
        }

        if extraDebtPayment > 0, let debt = debts.first(where: { $0.extraCents > 0 }) {
            steps.append(("Pay down high-interest debt",
                          "The remaining **\(Money.exact(extraDebtPayment))** goes toward your \(debt.name.lowercased()) each month."))
        } else if remainingCashCents > 0 {
            steps.append(("Keep the rest flexible",
                          "The remaining **\(Money.whole(remainingCashCents))** each month stays yours to direct."))
        }
        return steps
    }

    var explanationTradeoff: String {
        guard currentEmployeeRate != adaptiveEmployeeRate else { return explanation.tradeoff }
        return "Your contribution moves from **\(SheetCopy.percent(currentEmployeeRate))** to **\(SheetCopy.percent(adaptiveEmployeeRate))** for now. After debt payoff, build \(fullTargetMonths == 3 ? "three" : "\(fullTargetMonths)") months of reserves before increasing contributions."
    }

    var supportingInputs: [SupportingInput] {
        var inputs = [SupportingInput(label: "Gross salary", value: Money.whole(annualSalaryCents), unit: "/yr")]
        for debt in debts {
            inputs.append(SupportingInput(label: "\(debt.name) balance", value: Money.whole(debt.balanceCents)))
            inputs.append(SupportingInput(label: "\(debt.name) APR", value: SheetCopy.percent(debt.apr)))
        }
        if debts.isEmpty {
            inputs.append(SupportingInput(label: "Retirement balance", value: Money.whole(retirementBalanceCents)))
        }
        inputs.append(SupportingInput(label: "Emergency cash", value: Money.whole(emergencyCashCents)))
        return inputs
    }
}
