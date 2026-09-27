import SwiftUI

/// Financial snapshot: the canonical inputs behind the plan, with source and as-of date.
/// No transaction feed or holdings drilldown (FRONTEND.md §3).
struct SnapshotSheet: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let profile = store.displayProfile
        SheetScaffold(title: "Financial snapshot") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.m) {
                    AvatarView(profile: profile, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name)
                            .font(.geist(19, .medium, relativeTo: .title3))
                            .foregroundStyle(Palette.textPrimary)
                        EmphasizedText("**\(profile.age)** · Retiring at **\(profile.retirementAge)**",
                                       size: 13, style: .footnote)
                    }
                    Spacer(minLength: Space.m)
                    DataModeBadge(mode: store.dataMode)
                }
                .padding(.top, 14)
                .padding(.bottom, 21)

                SnapshotSection(title: "Income and costs", rows: [
                    ("Gross salary", Money.whole(profile.annualSalaryCents), "/yr"),
                    ("Take-home pay", Money.exact(profile.monthlyTakeHomeCents), "/mo"),
                    ("Living expenses", Money.exact(profile.monthlyLivingCents), "/mo")
                ])

                SnapshotSection(title: "Retirement", rows: [
                    ("Account balance", Money.whole(profile.retirementBalanceCents), nil),
                    ("Current contribution", SheetCopy.percent(profile.currentEmployeeRate), "of pay"),
                    ("Retirement age", "\(profile.retirementAge)", nil)
                ])

                SnapshotSection(title: "Cash", rows: [
                    ("Emergency cash", Money.whole(profile.emergencyCashCents), nil),
                    ("Covers", SheetCopy.months(profile.emergencyMonths), "of expenses")
                ])

                SnapshotSection(title: "Debt", rows: debtRows(profile), isLast: true)

                SourceCaption(lines: [SheetCopy.source(profile), SheetCopy.asOf, Disclosure.fictional])
                    .padding(.top, Space.l)
            }
        }
    }

    private func debtRows(_ profile: Profile) -> [(String, String, String?)] {
        guard !profile.debts.isEmpty else { return [("Balances", "None", nil)] }
        return profile.debts.flatMap { debt -> [(String, String, String?)] in
            [("\(debt.name) balance", Money.whole(debt.balanceCents), nil),
             ("\(debt.name) APR", SheetCopy.percent(debt.apr), nil),
             ("Minimum payment", Money.exact(debt.minimumCents), "/mo")]
        }
    }
}

private struct SnapshotSection: View {
    let title: String
    let rows: [(String, String, String?)]
    var isLast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetSectionTitle(title)
                .padding(.top, 19)
                .padding(.bottom, 8)
            ForEach(rows, id: \.0) { row in
                InputRow(label: row.0, value: row.1, unit: row.2)
            }
            if !isLast {
                Hairline(color: Palette.hairlineStrong)
                    .padding(.top, 16)
            }
        }
    }
}
