import SwiftUI

/// Every dollar accounted for: contributions, cash priorities, debt, reserves, allocation.
/// Each section opens the backend explanation via **Why?**.
struct PlanView: View {
    @EnvironmentObject private var store: AppStore

    private var profile: Profile { store.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                contributions.planCard()
                cashPriorities.planCard()
                ForEach(profile.debts) { debt in
                    debtSection(debt).planCard(tint: Palette.copper)
                }
                emergency.planCard()
                allocation.planCard()
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(AmbientGlow())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader {
                Text("Your plan")
                    .font(.geist(32, .bold, relativeTo: .largeTitle))
                    .tracking(-0.7)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            } trailing: {
                HeaderAvatarButton()
            }
        }
        .animation(Motion.reveal, value: profile.id)
    }

    // MARK: Retirement contributions

    private var contributions: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Retirement contributions", symbol: "building.columns.fill") { store.sheet = .explanation }
                .padding(.bottom, 7)

            HStack(alignment: .center) {
                Text(OverviewCopy.percent(profile.adaptiveEmployeeRate))
                    .font(.geist(45, .semibold, relativeTo: .largeTitle))
                    .tracking(-0.7)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Space.m)
                VStack(alignment: .trailing, spacing: Space.xs) {
                    (Text(Money.whole(profile.employeeMonthlyCents)).font(.geist(20, .semibold, relativeTo: .title3))
                     + Text(" / month").font(.geist(20, .medium, relativeTo: .title3)))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text("Your employee contribution")
                        .font(.geist(12, .regular, relativeTo: .caption))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(minHeight: 64)
            .accessibilityElement(children: .combine)
            .padding(.bottom, 11)

            PlanRow(title: "Estimated take-home cost", value: Money.exact(profile.takeHomeCostCents))
            PlanRow(title: "Employer adds", value: Money.exact(profile.employerMonthlyCents))

            if profile.matchCaptured {
                Label {
                    Text("Full employer match preserved")
                        .font(.geist(13, .medium, relativeTo: .footnote))
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .labelStyle(TightLabelStyle(spacing: 7))
                .foregroundStyle(Palette.lavender)
                .frame(minHeight: 28)
            }
        }
    }

    // MARK: Monthly cash priorities

    private var cashPriorities: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Monthly cash priorities", symbol: "arrow.triangle.branch") { store.sheet = .explanation }
            Text("After essentials and debt minimums")
                .font(.geist(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, Space.l)

            CashPriorityBand(priorities: profile.cashPriorities)
                .padding(.bottom, Space.m)

            ForEach(profile.cashPriorities) { priority in
                CashPriorityRow(priority: priority, title: PlanCopy.title(for: priority))
            }

            PlanCopy.essentials(for: profile)
                .font(.geist(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
        }
    }

    // MARK: Debt

    private func debtSection(_ debt: Debt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: PlanCopy.debtTitle(debt), symbol: "creditcard.fill", tint: Palette.peach) { store.sheet = .explanation }

            HStack {
                Text(Money.whole(debt.balanceCents))
                    .font(.geist(29, .semibold, relativeTo: .title))
                    .tracking(-0.7)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                (Text(OverviewCopy.percent(debt.apr)).font(.geist(12, .semibold, relativeTo: .caption))
                 + Text(" APR").font(.geist(12, .medium, relativeTo: .caption)))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 26)
                    .glassCapsule(tint: Palette.copper, interactive: false)
            }
            .frame(minHeight: 46)
            .accessibilityElement(children: .combine)
            .padding(.bottom, 5)

            PlanRow(title: "Required minimum", value: Money.exact(debt.minimumCents))
            PlanRow(title: "Additional payment", value: Money.exact(debt.extraCents))
            PlanRow(title: "Total monthly payment", value: Money.exact(debt.minimumCents + debt.extraCents))

            Text(PlanCopy.debtNote(debt))
                .font(.geist(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.m)
        }
    }

    // MARK: Emergency savings

    private var emergency: some View {
        let fullTargetCents = profile.monthlyLivingCents * Int64(profile.fullTargetMonths)
        let progress = min(profile.emergencyMonths / Double(profile.fullTargetMonths), 1)
        let starterFunded = profile.emergencyMonths >= Double(profile.starterTargetMonths)
        let fullFunded = profile.emergencyMonths >= Double(profile.fullTargetMonths)

        return VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Emergency savings", symbol: "umbrella.fill", tint: Palette.positive) { store.sheet = .explanation }

            HStack {
                MonthsLabel(months: profile.emergencyMonths, size: 28)
                    .tracking(-0.7)
                Spacer()
                Text(Money.whole(profile.emergencyCashCents))
                    .font(.geist(18, .semibold, relativeTo: .headline))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minHeight: 46)
            .accessibilityElement(children: .combine)
            .padding(.bottom, Space.m)

            SplitBar(fraction: progress, height: 6, leading: Palette.lavender, trailing: Palette.raised)
                .accessibilityLabel("Reserve progress")
                .accessibilityValue("\(OverviewCopy.monthsCount(profile.emergencyMonths)) of \(profile.fullTargetMonths) months")
                .padding(.bottom, 10)

            PlanRow(title: PlanCopy.target("Starter target", months: profile.starterTargetMonths),
                    value: starterFunded ? Text("Funded") : Text(Money.whole(profile.monthlyLivingCents * Int64(profile.starterTargetMonths))),
                    valueColor: starterFunded ? Palette.lavender : Palette.textPrimary,
                    valueWeight: starterFunded ? .medium : .semibold)
            PlanRow(title: PlanCopy.target("Full target", months: profile.fullTargetMonths),
                    value: fullFunded ? Text("Funded") : Text(Money.whole(fullTargetCents)),
                    valueColor: fullFunded ? Palette.lavender : Palette.textPrimary,
                    valueWeight: fullFunded ? .medium : .semibold)
        }
    }

    // MARK: Target-date foundation

    private var allocation: some View {
        let stocks = profile.equityWeight
        return VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Target-date foundation", symbol: "chart.pie.fill") { store.sheet = .explanation }
                .padding(.bottom, 9)

            SplitBar(fraction: stocks, height: 8, leading: Palette.lavender, trailing: Palette.textSecondary)
                .accessibilityLabel(Disclosure.allocationLabel)
                .accessibilityValue("Stocks \(OverviewCopy.percent(stocks)), bonds \(OverviewCopy.percent(1 - stocks))")
                .padding(.bottom, 11)

            PlanRow(title: "Stocks", value: Text(OverviewCopy.percent(stocks)), valueColor: Palette.lavender)
            PlanRow(title: "Bonds", value: OverviewCopy.percent(1 - stocks))

            Text(Disclosure.allocationCopy)
                .font(.geist(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            Text(Disclosure.allocationLabel + ".")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
        }
    }
}

// MARK: - Pieces

/// Icon badge, 19 pt SemiBold section title, and a trailing glass **Why?** pill.
private struct PlanSectionHeader: View {
    let title: String
    let symbol: String
    var tint: Color = Palette.lavender
    let why: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            IconBadge(systemName: symbol, tint: tint)
            Text(title)
                .font(.geist(19, .semibold, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            Button(action: why) {
                Text("Why?")
                    .font(.geist(13, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.lavender)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .glassCapsule()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Why? \(title)")
        }
        .frame(minHeight: 44)
    }
}

private extension View {
    /// A Plan section on a glass card.
    func planCard(tint: Color? = nil) -> some View {
        padding(.horizontal, 18)
            .padding(.top, Space.m)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(tint: tint)
    }
}

/// Label / value row: 15 pt Regular secondary label, 16 pt tabular value.
private struct PlanRow: View {
    let title: Text
    let value: Text
    var valueColor: Color = Palette.textPrimary
    var valueWeight: GeistWeight = .semibold

    init(title: String, value: String) {
        self.title = Text(title)
        self.value = Text(value)
    }

    init(title: Text, value: Text, valueColor: Color = Palette.textPrimary, valueWeight: GeistWeight = .semibold) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
        self.valueWeight = valueWeight
    }

    init(title: String, value: Text, valueColor: Color = Palette.textPrimary) {
        self.init(title: Text(title), value: value, valueColor: valueColor)
    }

    var body: some View {
        HStack {
            title
                .font(.geist(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.m)
            value
                .font(.geist(16, valueWeight, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }
}

/// Two-part rounded bar with a 3 pt gap (reserve progress, stocks/bonds).
private struct SplitBar: View {
    let fraction: Double
    let height: CGFloat
    let leading: Color
    let trailing: Color

    var body: some View {
        GeometryReader { proxy in
            let f = min(max(fraction, 0), 1)
            let gap: CGFloat = f > 0 && f < 1 ? 3 : 0
            let lead = (proxy.size.width - gap) * f
            HStack(spacing: gap) {
                if f > 0 {
                    Capsule().fill(leading).frame(width: lead)
                }
                if f < 1 {
                    Capsule().fill(trailing)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
    }
}

private struct TightLabelStyle: LabelStyle {
    var spacing: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Copy

enum PlanCopy {
    static func title(for priority: CashPriority) -> String {
        priority.kind == .retirement ? "Retirement take-home cost" : priority.title
    }

    static func debtTitle(_ debt: Debt) -> String {
        debt.name == "Credit card" ? "Credit card debt" : debt.name
    }

    static func debtNote(_ debt: Debt) -> String {
        debt.extraCents > 0
            ? "After this debt is paid off, rebuild savings before increasing contributions."
            : "At \(OverviewCopy.percent(debt.apr)) APR, the minimum payment keeps this on schedule without slowing saving."
    }

    /// "Starter target · **1** month"
    static func target(_ label: String, months: Int) -> Text {
        Text("\(label) · ")
            + Text("\(months)").font(.geist(15, .medium, relativeTo: .subheadline))
            + Text(months == 1 ? " month" : " months")
    }

    /// "Essentials: **$3,600** living expenses + **$400** debt minimum each month."
    static func essentials(for profile: Profile) -> Text {
        let bold = { (s: String) in Text(s).font(.geist(13, .medium, relativeTo: .footnote)) }
        let minimums = profile.debts.reduce(Int64(0)) { $0 + $1.minimumCents }
        var text = Text("Essentials: ") + bold(Money.whole(profile.monthlyLivingCents)) + Text(" living expenses")
        if minimums > 0 {
            text = text + Text(" + ") + bold(Money.whole(minimums)) + Text(" debt minimum")
        }
        return text + Text(" each month.")
    }
}

#Preview {
    PlanView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
