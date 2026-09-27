import SwiftUI

/// Every dollar accounted for: contributions, cash priorities, debt, reserves, allocation.
/// Each section leads with a graphic and a single hero figure; supporting numbers sit in the
/// graphic itself rather than in label/value rows. **Why?** opens the backend explanation.
struct PlanView: View {
    @EnvironmentObject private var store: AppStore

    @State private var isScrolled = !ScreenHeaderScroll.isTrackable

    private var profile: Profile { store.displayProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                contributions
                divider
                cashPriorities
                ForEach(profile.debts) { debt in
                    divider
                    debtSection(debt)
                }
                divider
                emergency
                divider
                allocation
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .tracksScrolled($isScrolled)
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(isScrolled: isScrolled) {
                Text("Your plan")
                    .font(.geist(32, .regular, relativeTo: .largeTitle))
                    .tracking(-0.7)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            } trailing: {
                HeaderAvatarButton()
            }
        }
        .animation(Motion.reveal, value: profile.id)
    }

    private var divider: some View {
        Hairline(color: Palette.hairlineStrong)
            .padding(.vertical, Space.xl)
    }

    // MARK: Retirement contributions

    private var contributions: some View {
        let total = profile.employeeMonthlyCents + profile.employerMonthlyCents
        return VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Retirement contributions") { store.sheet = .explanation }
                .padding(.bottom, Space.m)

            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                HeroFigure(text: OverviewCopy.percent(profile.adaptiveEmployeeRate))
                Text("of salary")
                    .font(.geist(15, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: Space.m)
                if profile.matchCaptured {
                    StatusChip(symbol: "checkmark.seal.fill", text: "Full match")
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, Space.xl)

            SegmentedBand(segments: [
                .init(label: "You", value: Money.whole(profile.employeeMonthlyCents),
                      weight: Double(profile.employeeMonthlyCents), colors: CashPriority.Kind.retirement.bandGradient),
                .init(label: "Employer", value: "+" + Money.whole(profile.employerMonthlyCents),
                      weight: Double(profile.employerMonthlyCents), colors: PlanPalette.employer)
            ])
            .padding(.bottom, Space.l)

            HStack(alignment: .top, spacing: Space.l) {
                StatBlock(value: Money.whole(total), unit: "/ mo", caption: "Into retirement")
                StatBlock(value: Money.exact(profile.takeHomeCostCents), unit: nil, caption: "Your take-home cost",
                          alignment: .trailing)
            }
        }
    }

    // MARK: Monthly cash priorities

    private var cashPriorities: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Monthly cash priorities") { store.sheet = .explanation }
                .padding(.bottom, Space.l)

            CashPriorityBand(priorities: profile.cashPriorities, height: 10)
                .padding(.bottom, Space.m)

            ForEach(profile.cashPriorities.filter { $0.amountCents > 0 }) { priority in
                CashPriorityRow(priority: priority, title: PlanCopy.tileTitle(for: priority))
            }
        }
    }

    // MARK: Debt

    private func debtSection(_ debt: Debt) -> some View {
        let total = debt.minimumCents + debt.extraCents
        var segments: [SegmentedBand.Segment] = [
            .init(label: "Minimum", value: Money.whole(debt.minimumCents),
                  weight: Double(debt.minimumCents), colors: PlanPalette.minimum)
        ]
        if debt.extraCents > 0 {
            segments.append(.init(label: "Extra", value: Money.exact(debt.extraCents),
                                  weight: Double(debt.extraCents), colors: CashPriority.Kind.debt.bandGradient))
        }

        return VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: PlanCopy.debtTitle(debt)) { store.sheet = .explanation }
                .padding(.bottom, Space.m)

            HStack(alignment: .firstTextBaseline) {
                HeroFigure(text: Money.whole(debt.balanceCents), size: 36)
                Spacer(minLength: Space.m)
                StatusChip(text: "\(OverviewCopy.percent(debt.apr)) APR", tint: Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, Space.xl)

            SegmentedBand(segments: segments)
                .padding(.bottom, Space.l)

            HStack(alignment: .top, spacing: Space.l) {
                StatBlock(value: Money.exact(total), unit: "/ mo", caption: "Total payment")
                if let cleared = PlanCopy.debtCleared(for: profile, debt: debt) {
                    StatBlock(value: cleared, unit: nil, caption: "Illustrative payoff", alignment: .trailing,
                              symbol: "flag.checkered")
                }
            }
            .padding(.bottom, Space.l)

            Footnote(text: PlanCopy.debtNote(debt))
        }
    }

    // MARK: Emergency savings

    private var emergency: some View {
        let fullTargetCents = profile.monthlyLivingCents * Int64(profile.fullTargetMonths)
        let starterFunded = profile.emergencyMonths >= Double(profile.starterTargetMonths)
        let fullFunded = profile.emergencyMonths >= Double(profile.fullTargetMonths)
        let beyond = profile.emergencyMonths - Double(profile.fullTargetMonths)

        return VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Emergency savings") { store.sheet = .explanation }
                .padding(.bottom, Space.m)

            HStack(alignment: .firstTextBaseline) {
                MonthsLabel(months: profile.emergencyMonths, size: 36)
                    .tracking(-1)
                Spacer(minLength: Space.m)
                Text(Money.whole(profile.emergencyCashCents))
                    .font(.numeral(16, .medium, relativeTo: .body))
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, Space.xl)

            MonthMeter(months: profile.emergencyMonths, target: profile.fullTargetMonths)
                .accessibilityLabel("Reserve progress")
                .accessibilityValue("\(OverviewCopy.monthsCount(profile.emergencyMonths)) of \(profile.fullTargetMonths) months")
                .padding(.bottom, Space.m)

            HStack(alignment: .top) {
                TargetMark(title: PlanCopy.monthsTitle("Starter", months: profile.starterTargetMonths),
                           value: starterFunded ? "Funded" : Money.whole(profile.monthlyLivingCents * Int64(profile.starterTargetMonths)),
                           funded: starterFunded)
                Spacer(minLength: Space.m)
                TargetMark(title: PlanCopy.monthsTitle("Full target", months: profile.fullTargetMonths),
                           value: fullFunded ? "Funded" : Money.whole(fullTargetCents),
                           funded: fullFunded, alignment: .trailing)
            }

            if beyond > 0 {
                Text("\(OverviewCopy.monthsCount(beyond)) \(beyond == 1 ? "month" : "months") beyond target")
                    .font(.geist(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Palette.textCaption)
                    .padding(.top, Space.m)
            }
        }
    }

    // MARK: Target-date foundation

    private var allocation: some View {
        let stocks = profile.equityWeight
        return VStack(alignment: .leading, spacing: 0) {
            PlanSectionHeader(title: "Target-date foundation") { store.sheet = .explanation }
                .padding(.bottom, Space.l)

            HStack(spacing: Space.xxl) {
                AllocationRing(stocks: stocks)
                    .frame(width: 112, height: 112)
                    .accessibilityLabel(Disclosure.allocationLabel)
                    .accessibilityValue("Stocks \(OverviewCopy.percent(stocks)), bonds \(OverviewCopy.percent(1 - stocks))")

                VStack(alignment: .leading, spacing: Space.l) {
                    LegendFigure(color: Palette.accent, title: "Stocks", value: OverviewCopy.percent(stocks))
                    LegendFigure(color: PlanPalette.bonds, title: "Bonds", value: OverviewCopy.percent(1 - stocks))
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .padding(.bottom, Space.xl)

            Footnote(text: Disclosure.allocationCopy)
                .padding(.bottom, Space.s)
            Text(Disclosure.allocationLabel + ".")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textQuiet)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Palette

private enum PlanPalette {
    /// Employer match: a paler, cooler green beside "You".
    static let employer = [Color(hex: 0x7FC98A), Color(hex: 0x5EA36C), Color(hex: 0x3A5E42)]
    /// Required minimum: muted, so the extra payment reads as the decision.
    static let minimum = [Color(hex: 0x5E5452), Color(hex: 0x4A4240), Color(hex: 0x332E2E)]
    static let bonds = Color(hex: 0x5C5F70)
}

// MARK: - Pieces

/// A 19 pt Medium section title with a trailing **Why?** link.
private struct PlanSectionHeader: View {
    let title: String
    let why: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(title)
                .font(.geist(19, .medium, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            Button(action: why) {
                Text("Why?")
                    .font(.geist(13, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Why? \(title)")
        }
    }
}

/// The section's single large figure.
private struct HeroFigure: View {
    let text: String
    var size: CGFloat = 52

    var body: some View {
        Text(text)
            .font(.numeral(size, .medium, relativeTo: .largeTitle))
            .tracking(-size * 0.055)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }
}

/// Small capsule status: "✓ Full match", "25% APR".
private struct StatusChip: View {
    var symbol: String? = nil
    let text: String
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.geist(12, .medium, relativeTo: .caption))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
        .glassCapsule(tint: tint, interactive: false)
    }
}

/// A proportional band whose segments carry their own label and amount.
private struct SegmentedBand: View {
    struct Segment: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let weight: Double
        let colors: [Color]
    }

    let segments: [Segment]
    var height: CGFloat = 60
    var gap: CGFloat = 4
    /// Keeps the smaller segment wide enough for its text.
    var minimumWidth: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            let widths = layout(proxy.size.width)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    ZStack(alignment: .bottomLeading) {
                        BandFill(colors: segment.colors, cornerRadius: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.label)
                                .font(.geist(11, .medium, relativeTo: .caption2))
                                .foregroundStyle(.white.opacity(0.72))
                            Text(segment.value)
                                .font(.numeral(16, .medium, relativeTo: .body))
                                .tracking(-0.4)
                                .foregroundStyle(Color(hex: 0xF9FFFA))
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 9)
                    }
                    .frame(width: widths[index])
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }

    private func layout(_ width: CGFloat) -> [CGFloat] {
        let available = width - gap * CGFloat(max(segments.count - 1, 0))
        let total = CGFloat(max(segments.reduce(0) { $0 + $1.weight }, 1))
        var widths = segments.map { max(available * CGFloat($0.weight) / total, minimumWidth) }
        let overflow = widths.reduce(0, +) - available
        if overflow > 0, let widest = widths.indices.max(by: { widths[$0] < widths[$1] }) {
            widths[widest] -= overflow
        }
        return widths
    }
}

/// Figure with a quiet unit and caption beneath.
private struct StatBlock: View {
    let value: String
    let unit: String?
    let caption: String
    var alignment: HorizontalAlignment = .leading
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(value)
                    .font(.numeral(20, .medium, relativeTo: .title3))
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.geist(13, .regular, relativeTo: .footnote))
                        .foregroundStyle(Palette.textCaption)
                }
            }
            Text(caption)
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
        .accessibilityElement(children: .combine)
    }
}

/// One capsule per month of the full target, filled by months saved.
private struct MonthMeter: View {
    let months: Double
    let target: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(target, 1), id: \.self) { index in
                let fill = min(max(months - Double(index), 0), 1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.raised)
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.accent, Color(hex: 0x7FC98A)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: proxy.size.width * fill)
                    }
                }
            }
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
    }
}

/// Reserve target under the meter: "Starter · 1 mo" over "✓ Funded" or its amount.
private struct TargetMark: View {
    let title: String
    let value: String
    let funded: Bool
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
            HStack(spacing: 4) {
                if funded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(value)
                    .font(funded ? .geist(14, .medium, relativeTo: .subheadline)
                                 : .numeral(14, .medium, relativeTo: .subheadline))
            }
            .foregroundStyle(funded ? Palette.accent : Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stocks / bonds ring with the equity share at its centre.
private struct AllocationRing: View {
    let stocks: Double
    var lineWidth: CGFloat = 12

    var body: some View {
        let gap = 0.012
        ZStack {
            ZStack {
                Circle()
                    .trim(from: gap, to: max(stocks - gap, gap))
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle()
                    .trim(from: min(stocks + gap, 1), to: max(1 - gap, min(stocks + gap, 1)))
                    .stroke(PlanPalette.bonds, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(OverviewCopy.percent(stocks))
                    .font(.numeral(20, .medium, relativeTo: .title3))
                    .tracking(-0.8)
                    .foregroundStyle(Palette.textPrimary)
                Text("stocks")
                    .font(.geist(11, .regular, relativeTo: .caption2))
                    .foregroundStyle(Palette.textCaption)
            }
        }
        .padding(lineWidth / 2)
    }
}

private struct LegendFigure: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.geist(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(value)
                .font(.numeral(24, .medium, relativeTo: .title2))
                .tracking(-0.9)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

/// Supporting sentence set small and quiet.
private struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.geist(13, .regular, relativeTo: .footnote))
            .foregroundStyle(Palette.textCaption)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Copy

enum PlanCopy {
    static func title(for priority: CashPriority) -> String {
        priority.kind == .retirement ? "Retirement take-home cost" : priority.title
    }

    /// Short card titles for the 2×2 priority grid.
    static func tileTitle(for priority: CashPriority) -> String {
        switch priority.kind {
        case .retirement: "Retirement cost"
        case .debt: "Extra debt payment"
        case .emergency: "Emergency savings"
        case .remaining: "Remaining cash"
        }
    }

    static func debtTitle(_ debt: Debt) -> String {
        debt.name == "Credit card" ? "Credit card debt" : debt.name
    }

    static func debtNote(_ debt: Debt) -> String {
        debt.extraCents > 0
            ? "After this debt is paid off, rebuild savings before increasing contributions."
            : "At \(OverviewCopy.percent(debt.apr)) APR, the minimum payment keeps this on schedule without slowing saving."
    }

    /// "Sep 2028" from Explore's illustrative timeline, when it marks this plan's payoff.
    static func debtCleared(for profile: Profile, debt: Debt) -> String? {
        guard debt.extraCents > 0,
              let month = ExploreTimeline.illustrative(for: profile).milestones.first(where: { $0.title == "Debt cleared" })?.month
        else { return nil }
        return ExploreTimeline.label(forMonth: month)
    }

    /// "Starter · 1 mo"
    static func monthsTitle(_ label: String, months: Int) -> String {
        "\(label) · \(months) mo"
    }
}

#Preview {
    PlanView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
