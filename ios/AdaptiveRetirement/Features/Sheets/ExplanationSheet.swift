import SwiftUI

/// "Why this plan?" — the saved plan's priorities, tradeoff and supporting inputs.
/// Every figure is read from the profile fixture; nothing is recalculated here.
struct ExplanationSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let profile = store.profile
        SheetScaffold(title: "Why this plan?") {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SheetFooterAction(title: "Got it") { dismiss() }
        }
    }
}

private struct PriorityStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.geist(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.lavender)
                .frame(width: 27, height: 27)
                .background(Circle().fill(Palette.raised))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.geist(17, .medium, relativeTo: .headline))
                    .foregroundStyle(Palette.textPrimary)
                EmphasizedText(detail, size: 14, style: .subheadline, lineSpacing: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Priority \(number). \(title). \(detail.replacingOccurrences(of: "**", with: ""))")
    }
}

// MARK: - Display copy assembled from fixture values

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
        extraDebtPayment > 0 ? "Keep your match.\nReduce costly debt." : explanation.headline
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
