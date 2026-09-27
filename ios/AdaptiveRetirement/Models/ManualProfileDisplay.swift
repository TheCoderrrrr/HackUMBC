import Foundation

extension Profile {
    static func personal(_ input: API.FinancialProfile) -> Profile {
        let debts = input.debts.map { item in
            Debt(id: item.id,
                 name: item.type == .creditCard ? "Credit card" : item.type == .studentLoan ? "Student loan" : "Other loan",
                 balanceCents: item.balanceCents, apr: item.apr,
                 minimumCents: item.minimumPaymentCents, extraCents: 0)
        }
        return Profile(
            id: input.id, name: input.name,
            initials: String(input.name.prefix(1)).uppercased(), subtitle: "Your numbers",
            age: input.age, retirementAge: input.retirementAge,
            annualSalaryCents: input.annualGrossSalaryCents,
            monthlyTakeHomeCents: input.monthlyTakeHomeCents,
            monthlyLivingCents: input.monthlyLivingExpensesCents,
            retirementBalanceCents: input.retirementBalanceCents,
            emergencyCashCents: input.emergencyCashCents,
            emergencyMonths: Double(input.emergencyCashCents) / Double(max(input.monthlyLivingExpensesCents, 1)),
            starterTargetMonths: 1, fullTargetMonths: 3,
            debts: debts, currentEmployeeRate: input.employeeContributionRate,
            adaptiveEmployeeRate: input.employeeContributionRate,
            employeeMonthlyCents: 0, employerMonthlyCents: 0, takeHomeCostCents: 0,
            matchCaptured: false,
            primaryActionTitle: "Review your plan", primaryActionDetail: "Calculated from your numbers.",
            primaryActionAmountCents: nil, cashPriorities: [], equityWeight: 0.5,
            explanation: Profile.morgan.explanation, origin: .none
        )
    }
}
