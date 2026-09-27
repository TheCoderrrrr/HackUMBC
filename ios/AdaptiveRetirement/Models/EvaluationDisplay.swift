import SwiftUI

// Maps a backend `API.Evaluation` onto the display `Profile` the screens already read.
// Every number comes from the engine response; this file only selects and sums fields
// from it. Names, copy and inputs the evaluation doesn't carry stay from `DemoData`.

extension Profile {
    /// The fixture with the engine's plan, derived state and projections applied. Inputs
    /// (salary, take-home, balances, debts) come from the profile the engine evaluated
    /// when it's known, so the snapshot shows the request's values, not `DemoData` (B4).
    func applying(_ loaded: LoadedEvaluation?) -> Profile {
        guard let loaded, loaded.evaluation.profileID == id else { return self }
        let e = loaded.evaluation
        let state = e.financialState
        let actions = e.plan.actions
        let input = loaded.apiProfile

        let contribution = actions.first { $0.category == .contribution }
        let rate = contribution?.employeeContributionRate ?? adaptiveEmployeeRate
        let employeeCents = contribution?.employeeContributionCents ?? employeeMonthlyCents
        let takeHomeCost = contribution?.monthlyCashCostCents ?? takeHomeCostCents

        let captured = state.employeeRateForFullMatch.map { rate + 1e-9 >= $0 } ?? matchCaptured
        // The actual employer match at the plan's rate lives in the contribution reason's
        // facts; the state fields only carry the current-rate and maximum amounts (B4).
        let employerCents: Int64
        let matchReason = e.plan.reasons.first {
            $0.code == "CAPTURE_EMPLOYER_MATCH" || $0.code == "MATCH_PARTIALLY_AFFORDABLE"
        }
        if case .int(let employer)? = matchReason?.facts["employer_contribution_cents"] {
            employerCents = employer
        } else if captured, let maximum = state.maximumMonthlyEmployerMatchCents {
            employerCents = maximum
        } else if abs(rate - currentEmployeeRate) < 1e-9, let current = state.currentMonthlyEmployerMatchCents {
            employerCents = current
        } else {
            employerCents = employerMonthlyCents
        }

        // Balances/APRs/minimums from the evaluated profile when it's available.
        let baseDebts: [Debt] = input?.debts.map { apiDebt in
            Debt(id: apiDebt.id, name: apiDebt.type.displayName, balanceCents: apiDebt.balanceCents,
                 apr: apiDebt.apr, minimumCents: apiDebt.minimumPaymentCents, extraCents: 0)
        } ?? debts

        let mappedDebts = baseDebts.map { debt -> Debt in
            guard let action = actions.first(where: { $0.debtID == debt.id }) else { return debt }
            // The engine's capped extra payment from the reason facts, not the action total
            // minus the fixture's minimum (B4).
            let reason = e.plan.reasons.first {
                $0.facts["debt_id"] == .string(debt.id) && $0.facts["extra_payment_cents"] != nil
            }
            let extra: Int64
            if case .int(let value)? = reason?.facts["extra_payment_cents"] {
                extra = value
            } else {
                extra = max(action.monthlyCashCostCents - debt.minimumCents, 0)
            }
            return Debt(id: debt.id, name: debt.name, balanceCents: debt.balanceCents, apr: debt.apr,
                        minimumCents: debt.minimumCents, extraCents: max(extra, 0))
        }
        let extraDebt = mappedDebts.reduce(Int64(0)) { $0 + $1.extraCents }
        func cost(_ category: API.RecommendationAction.Category) -> Int64 {
            actions.filter { $0.category == category }.reduce(0) { $0 + $1.monthlyCashCostCents }
        }
        let primaryExtra = e.plan.primaryAction?.debtID.flatMap { id in mappedDebts.first { $0.id == id }?.extraCents }

        var explanation = self.explanation
        if e.explanation.source == .ai {
            explanation = Explanation(headline: explanation.headline, narrative: e.explanation.narrative,
                                      priorities: explanation.priorities, facts: explanation.facts,
                                      tradeoff: explanation.tradeoff, checks: explanation.checks)
        }

        var result = Profile(
            id: id, name: name, initials: initials, subtitle: subtitle,
            age: input?.age ?? age, retirementAge: input?.retirementAge ?? retirementAge,
            annualSalaryCents: input?.annualGrossSalaryCents ?? annualSalaryCents,
            monthlyTakeHomeCents: input?.monthlyTakeHomeCents ?? monthlyTakeHomeCents,
            monthlyLivingCents: input?.monthlyLivingExpensesCents ?? monthlyLivingCents,
            retirementBalanceCents: input?.retirementBalanceCents ?? retirementBalanceCents,
            emergencyCashCents: input?.emergencyCashCents ?? emergencyCashCents,
            emergencyMonths: state.emergencyMonths,
            starterTargetMonths: starterTargetMonths, fullTargetMonths: fullTargetMonths,
            debts: mappedDebts,
            currentEmployeeRate: input?.employeeContributionRate ?? currentEmployeeRate,
            adaptiveEmployeeRate: rate,
            employeeMonthlyCents: employeeCents, employerMonthlyCents: employerCents,
            takeHomeCostCents: takeHomeCost, matchCaptured: captured,
            primaryActionTitle: primaryActionTitle, primaryActionDetail: primaryActionDetail,
            primaryActionAmountCents: (primaryExtra ?? 0) > 0 ? primaryExtra : nil,
            cashPriorities: [
                CashPriority(id: "ret", kind: .retirement, title: "Retirement cost", amountCents: takeHomeCost),
                CashPriority(id: "debt", kind: .debt, title: "Additional debt payment", amountCents: extraDebt),
                CashPriority(id: "emg", kind: .emergency, title: "Emergency savings", amountCents: cost(.emergency)),
                CashPriority(id: "rem", kind: .remaining, title: "Remaining cash", amountCents: cost(.cashFlow))
            ],
            equityWeight: state.baselineEquityWeight,
            explanation: explanation,
            origin: loaded.origin
        )
        result.evaluation = e
        return result
    }
}

extension API.Projection {
    /// Retirement balance at the start of each year from today: `years + 1` values.
    func yearlyRetirementBalances(years: Int) -> [Int64] {
        guard !points.isEmpty else { return [] }
        return (0...max(years, 0)).map { retirementBalance(atYear: $0) ?? points[0].retirementBalanceCents }
    }

    func retirementBalance(atYear year: Int) -> Int64? {
        points.last { $0.month <= year * 12 }?.retirementBalanceCents
    }
}

extension API.Debt.Kind {
    /// Display name for a debt the engine evaluated ("Credit card"), matching fixture style.
    var displayName: String {
        switch self {
        case .creditCard: return "Credit card"
        case .studentLoan: return "Student loan"
        case .other: return "Debt"
        }
    }
}

// MARK: - Reason-code copy (REPORT B3)

/// One short copy template per reason code, with amounts filled from the reason's
/// facts, so headlines and details follow the engine's primary action instead of
/// per-profile fixture copy. The backend owns the codes and facts (BACKEND.md §9).
enum ReasonCopy {
    /// The primary action's headline code: the first code that isn't boilerplate,
    /// mirroring the backend's template selection.
    static func primaryCode(in evaluation: API.Evaluation) -> String? {
        guard let action = evaluation.plan.primaryAction else { return nil }
        if action.status == .maintain, action.reasonCodes.contains("MAINTAIN_CONTRIBUTION") {
            return "MAINTAIN_CONTRIBUTION"
        }
        return action.reasonCodes.first { !["SIMPLIFIED_TAX_ESTIMATE", "BASELINE_ALLOCATION_RETAINED"].contains($0) }
    }

    private static func reason(in evaluation: API.Evaluation, code: String) -> API.Reason? {
        let debtID = evaluation.plan.primaryAction?.debtID
        return evaluation.plan.reasons.first {
            $0.code == code && (debtID == nil || $0.facts["debt_id"] == .string(debtID!))
        }
    }

    private static func cents(_ reason: API.Reason?, _ key: String) -> Int64? {
        guard case .int(let value)? = reason?.facts[key] else { return nil }
        return value
    }

    private static func rate(_ reason: API.Reason?, _ key: String) -> Double? {
        guard case .double(let value)? = reason?.facts[key] else { return nil }
        return value
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)))
    }

    /// Headline for the primary action (Overview's next step, the explanation sheet).
    static func headline(for evaluation: API.Evaluation) -> String {
        switch primaryCode(in: evaluation) {
        case "HIGH_APR_DEBT": return "Reduce costly debt."
        case "CAPTURE_EMPLOYER_MATCH": return "Capture your full employer match."
        case "MATCH_PARTIALLY_AFFORDABLE": return "Capture what match you can."
        case "CRITICAL_LIQUIDITY": return "Build a safety cushion first."
        case "BUILD_STARTER_RESERVE": return "Build your starter reserve."
        case "BUILD_FULL_RESERVE": return "Build your full reserve."
        case "INCREASE_RETIREMENT_SAVING": return "Increase your retirement saving."
        case "MAINTAIN_CONTRIBUTION": return "Stay the course."
        case "CASH_FLOW_SHORTFALL": return "Cover the essentials first."
        case "MISSING_REQUIRED_INPUT": return "Confirm your plan details."
        default: return "Your next step."
        }
    }

    /// Detail sentence for the primary action; nil when the code has no template, so the
    /// caller can fall back to fixture copy in preview.
    static func detail(for evaluation: API.Evaluation, profile: Profile) -> Text? {
        guard let code = primaryCode(in: evaluation) else { return nil }
        let reason = reason(in: evaluation, code: code)
        let emphasis = Font.geist(13, .medium, relativeTo: .footnote)
        switch code {
        case "HIGH_APR_DEBT":
            // The debt receiving the payment, not just the first debt (REPORT E3).
            let debtID = evaluation.plan.primaryAction?.debtID
            let name = profile.debts.first { $0.id == debtID }?.name.lowercased() ?? "high-APR debt"
            if let extra = cents(reason, "extra_payment_cents"), extra > 0 {
                return Text(Money.exact(extra)).font(emphasis)
                    + Text(" extra toward your \(name) each month.")
            }
            return Text("Extra cash goes toward your \(name) each month.")
        case "MAINTAIN_CONTRIBUTION":
            if let rate = rate(reason, "employee_contribution_rate"),
               let amount = cents(reason, "employee_contribution_cents") {
                return Text("Maintain your \(percent(rate)) contribution — ")
                    + Text(Money.whole(amount)).font(emphasis) + Text(" a month.")
            }
            return nil
        case "CAPTURE_EMPLOYER_MATCH":
            if let employee = cents(reason, "employee_contribution_cents"),
               let employer = cents(reason, "employer_contribution_cents") {
                return Text("Contribute ") + Text(Money.whole(employee)).font(emphasis)
                    + Text(" to capture ") + Text(Money.whole(employer)).font(emphasis)
                    + Text(" of employer matching each month.")
            }
            return nil
        case "MATCH_PARTIALLY_AFFORDABLE":
            if let employee = cents(reason, "employee_contribution_cents"),
               let required = rate(reason, "required_employee_rate") {
                return Text("Contribute ") + Text(Money.whole(employee)).font(emphasis)
                    + Text(" this month — the full match needs \(percent(required)).")
            }
            return nil
        case "CRITICAL_LIQUIDITY", "BUILD_STARTER_RESERVE", "BUILD_FULL_RESERVE":
            if let added = cents(reason, "cash_added_cents") {
                let target = code == "CRITICAL_LIQUIDITY" ? "a small safety reserve"
                    : code == "BUILD_STARTER_RESERVE" ? "a one-month cash cushion"
                    : "three months of expenses"
                return Text("Add ") + Text(Money.whole(added)).font(emphasis)
                    + Text(" toward \(target) each month.")
            }
            return nil
        case "INCREASE_RETIREMENT_SAVING":
            if let original = cents(reason, "original_employee_contribution_cents"),
               let increased = cents(reason, "employee_contribution_cents") {
                return Text("Raise your contribution from \(Money.whole(original)) to ")
                    + Text(Money.whole(increased)).font(emphasis) + Text(" a month.")
            }
            return nil
        case "CASH_FLOW_SHORTFALL":
            if let shortfall = cents(reason, "shortfall_cents") {
                return Text("Essentials exceed monthly resources by ")
                    + Text(Money.exact(shortfall)).font(emphasis) + Text(".")
            }
            return nil
        case "MISSING_REQUIRED_INPUT":
            return Text("Confirm your employer match details to unlock a full plan.")
        default:
            return nil
        }
    }
}
