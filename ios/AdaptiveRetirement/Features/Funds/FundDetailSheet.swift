import SwiftUI

/// Everything behind one shortlisted fund, each figure with its source and date. Past
/// returns and hypothetical scenarios are kept in separate sections and never mixed.
struct FundDetailSheet: View {
    let recommendation: API.Funds.Recommendation
    let detail: API.Funds.Detail?
    let shortlist: API.Funds.Shortlist?

    var body: some View {
        SheetScaffold(title: "Fund details", subtitle: FundCard.identity(recommendation, detail)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(recommendation.name)
                    .font(.geist(22, .regular, relativeTo: .title2))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                let availability = FundCopy.availability(recommendation.availabilityLabel)
                StatusChip(symbol: availability.confirmed ? "checkmark.seal.fill" : "info.circle",
                           text: availability.text,
                           tint: availability.confirmed ? Palette.accent : Palette.textSecondary)
                    .padding(.top, Space.m)

                if let detail {
                    fees(detail.fees)
                    mix(detail)
                } else {
                    section("Sources") { Footnote(text: "Insufficient data: the server sent no sourced detail for this fund.") }
                }
                fit
                pastPerformance
                hypothetical
                if let detail {
                    links(detail)
                    if !detail.caveats.isEmpty { caveats(detail.caveats) }
                }
                if let shortlist {
                    SourceCaption(lines: [shortlist.hypotheticalDisclosure])
                        .padding(.top, Space.xl)
                }
            }
        }
    }

    // MARK: Sections

    private func fees(_ fees: API.Funds.FeeDetail) -> some View {
        section("Fees") {
            InputRow(label: "Expense ratio", value: FundCopy.fee(fees.appliedExpenseRatio),
                     unit: fees.waiverActive ? "after waiver" : nil)
            if fees.waiverActive {
                InputRow(label: "Before the waiver", value: FundCopy.fee(fees.grossExpenseRatio))
            }
            InputRow(label: "Underlying-fund costs", value: FundCopy.fee(fees.acquiredFundFees))
            if fees.waiverActive, let ends = fees.waiverEnds {
                Footnote(text: "\(FundCopy.fee(fees.grossExpenseRatio)) before a \(FundCopy.fee(fees.feeWaiver)) waiver that runs through \(FundCopy.asOf(ends)). Includes \(FundCopy.fee(fees.acquiredFundFees)) of underlying-fund costs. \(fees.waiverTerms)")
                    .padding(.top, Space.s)
            }
            Footnote(text: "Fee table as of \(FundCopy.asOf(fees.asOfDate)).")
                .padding(.top, Space.s)
        }
    }

    private func mix(_ detail: API.Funds.Detail) -> some View {
        section("Current mix") {
            SegmentedBand(segments: FundCard.mix(recommendation), height: 52, minimumWidth: 70)
                .padding(.bottom, Space.m)
            ForEach(detail.allocation.reportedCategories, id: \.label) { category in
                // percent_of_net_assets is already a percent, not a fraction.
                InputRow(label: category.label, value: String(format: "%.1f%%", category.percentOfNetAssets))
            }
            Footnote(text: "As of \(FundCopy.asOf(detail.allocation.asOfDate)) from the issuer's shareholder report. \(detail.allocation.mappingNote)")
                .padding(.top, Space.s)
            Footnote(text: detail.glidePath)
                .padding(.top, Space.s)
        }
    }

    private var fit: some View {
        section("Why it matched") {
            VStack(spacing: Space.m) {
                FitRow(title: "Target year near yours", value: recommendation.scoreComponents.horizonFit)
                FitRow(title: "Stock share near your risk choice", value: recommendation.scoreComponents.riskFit)
                FitRow(title: "Low cost", value: recommendation.scoreComponents.feeFit)
            }
            Footnote(text: "Risk band \(recommendation.riskBand) of 5 comes from the current stock share only, not volatility. It is a model output, not a suitability review.")
                .padding(.top, Space.m)
        }
    }

    private var pastPerformance: some View {
        section("Past performance") {
            if let first = recommendation.historicalReturns.first {
                Footnote(text: "Average annual total returns to \(FundCopy.asOf(first.asOfDate)). Past results don't predict future returns.")
                    .padding(.bottom, Space.s)
                ForEach(recommendation.historicalReturns, id: \.periodYears) { item in
                    InputRow(label: item.periodYears == 1 ? "1 year" : "\(item.periodYears) years",
                             value: FundCopy.signed(item.annualizedReturnRate))
                }
            } else {
                Footnote(text: "Not available.")
            }
        }
    }

    private var hypothetical: some View {
        section("Hypothetical illustration") {
            let scenarios = recommendation.hypotheticalScenarios
            if let base = scenarios.first(where: { $0.label == "base" }) ?? scenarios.first {
                Footnote(text: "\(Money.whole(base.hypotheticalStartCents)) over \(base.years) years if today's mix never changed. Not a forecast.")
                    .padding(.bottom, Space.s)
                ForEach(scenarios, id: \.label) { scenario in
                    InputRow(label: "\(FundCopy.scenarioLabel(scenario.label)) (\(FundCopy.signed(scenario.annualNetReturnRate))/yr)",
                             value: Money.whole(scenario.hypotheticalEndCents))
                }
            } else {
                Footnote(text: "Insufficient data.")
            }
        }
    }

    private func links(_ detail: API.Funds.Detail) -> some View {
        section("Sources") {
            VStack(alignment: .leading, spacing: 0) {
                SourceLink(title: "Prospectus, filed \(FundCopy.asOf(detail.prospectus.filedDate))", url: detail.prospectus.url)
                SourceLink(title: "Fee table", url: detail.fees.evidenceURL)
                SourceLink(title: "Holdings, \(FundCopy.asOf(detail.allocation.asOfDate))", url: detail.allocation.evidenceURL)
            }
        }
    }

    private func caveats(_ items: [String]) -> some View {
        section("Caveats") {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(Palette.textCaption)
                            .frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        EmphasizedText(item, size: 14, style: .subheadline, lineSpacing: 3)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline(color: Palette.hairlineStrong)
                .padding(.top, Space.xl)
            SheetSectionTitle(title)
                .padding(.top, 19)
                .padding(.bottom, Space.s)
            content()
        }
    }
}

/// A 0–100 bar for one component of the server's fit score.
private struct FitRow: View {
    let title: String
    let value: Double

    var body: some View {
        let clamped = min(max(value, 0), 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.geist(14, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(Int((clamped * 100).rounded()))")
                    .font(.numeral(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.raised)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.accent, Color(hex: 0x7FC98A)], startPoint: .top, endPoint: .bottom))
                        .frame(width: proxy.size.width * clamped)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int((clamped * 100).rounded())) out of 100")
    }
}

/// An outbound document link; opens in Safari.
private struct SourceLink: View {
    let title: String
    let url: String

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: Space.s) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .medium))
                    Text(title)
                        .font(.geist(15, .medium, relativeTo: .subheadline))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Opens in Safari")
        }
    }
}
