import Foundation

// Maps a backend `API.Evaluation` onto the display `Profile` the screens already read.
// Every number comes from the engine response; this file only selects and sums fields
// from it. Names, copy and inputs the evaluation doesn't carry stay from `DemoData`.

extension Profile {
    /// The fixture with the engine's plan, derived state and projections applied.
    func applying(_ loaded: LoadedEvaluation?) -> Profile {
        guard let loaded, loaded.evaluation.profileID == id else { return self }
        let e = loaded.evaluation
        let state = e.financialState
        let actions = e.plan.actions

        let contribution = actions.first { $0.category == .contribution }
        let rate = contribution?.employeeContributionRate ?? adaptiveEmployeeRate
        let employeeCents = contribution?.employeeContributionCents ?? employeeMonthlyCents
        let takeHomeCost = contribution?.monthlyCashCostCents ?? takeHomeCostCents

        // The engine reports match at the current rate and at the full-match rate; pick whichever applies.
        let captured = state.employeeRateForFullMatch.map { rate + 1e-9 >= $0 } ?? matchCaptured
        let employerCents: Int64
        if captured, let maximum = state.maximumMonthlyEmployerMatchCents {
            employerCents = maximum
        } else if abs(rate - currentEmployeeRate) < 1e-9, let current = state.currentMonthlyEmployerMatchCents {
            employerCents = current
        } else {
            employerCents = employerMonthlyCents
        }

        let mappedDebts = debts.map { debt -> Debt in
            guard let action = actions.first(where: { $0.debtID == debt.id }) else { return debt }
            return Debt(id: debt.id, name: debt.name, balanceCents: debt.balanceCents, apr: debt.apr,
                        minimumCents: debt.minimumCents,
                        extraCents: max(action.monthlyCashCostCents - debt.minimumCents, 0))
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
            age: age, retirementAge: retirementAge,
            annualSalaryCents: annualSalaryCents, monthlyTakeHomeCents: monthlyTakeHomeCents,
            monthlyLivingCents: monthlyLivingCents,
            retirementBalanceCents: retirementBalanceCents, emergencyCashCents: emergencyCashCents,
            emergencyMonths: state.emergencyMonths,
            starterTargetMonths: starterTargetMonths, fullTargetMonths: fullTargetMonths,
            debts: mappedDebts,
            currentEmployeeRate: currentEmployeeRate, adaptiveEmployeeRate: rate,
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
