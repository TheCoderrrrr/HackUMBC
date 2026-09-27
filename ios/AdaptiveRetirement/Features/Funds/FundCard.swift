import SwiftUI

/// One ranked fund: identity, availability, the three headline figures and today's mix.
/// Tapping opens the sourced detail sheet.
struct FundCard: View {
    let rank: Int
    let recommendation: API.Funds.Recommendation
    let detail: API.Funds.Detail?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Text("\(rank)")
                        .font(.geist(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 27, height: 27)
                        .background(Circle().fill(Palette.raised))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.name)
                            .font(.geist(17, .medium, relativeTo: .headline))
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(FundCard.identity(recommendation, detail))
                            .font(.geist(12, .regular, relativeTo: .caption))
                            .foregroundStyle(Palette.textCaption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                let availability = FundCopy.availability(recommendation.availabilityLabel)
                StatusChip(symbol: availability.confirmed ? "checkmark.seal.fill" : "info.circle",
                           text: availability.text,
                           tint: availability.confirmed ? Palette.accent : Palette.textSecondary)
                    .padding(.top, Space.m)

                HStack(alignment: .top, spacing: Space.m) {
                    StatBlock(value: FundCopy.fee(recommendation.expenseRatio), unit: nil,
                              caption: detail?.fees.waiverActive == true ? "Net of waiver" : "Expense ratio")
                    StatBlock(value: String(recommendation.targetYear), unit: nil, caption: "Target year",
                              alignment: .center)
                    StatBlock(value: "\(recommendation.riskBand)", unit: "/ 5", caption: "Risk band",
                              alignment: .trailing)
                }
                .padding(.top, Space.l)

                SegmentedBand(segments: FundCard.mix(recommendation), height: 52, minimumWidth: 70)
                    .padding(.top, Space.l)

                HStack(spacing: 6) {
                    Text("As of \(FundCopy.asOf(recommendation.factsAsOfDate)) · sources, returns and scenarios")
                        .font(.geist(12, .regular, relativeTo: .caption))
                        .foregroundStyle(Palette.textCaption)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.textCaption)
                }
                .padding(.top, Space.m)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99, dim: 0.85))
        .accessibilityHint("Opens sources, past returns and hypothetical scenarios")
    }

    /// "BlackRock · Class K · ABCDX · share class C000123".
    static func identity(_ recommendation: API.Funds.Recommendation, _ detail: API.Funds.Detail?) -> String {
        var parts: [String] = []
        if let detail {
            parts.append(detail.issuer)
            parts.append(detail.className)
            if let ticker = detail.ticker { parts.append(ticker) }
        }
        parts.append("share class \(recommendation.shareClassID)")
        return parts.joined(separator: " · ")
    }

    /// Stocks / Bonds / Other from the fund's current weights; empty buckets are left out.
    static func mix(_ recommendation: API.Funds.Recommendation) -> [SegmentedBand.Segment] {
        [("Stocks", recommendation.equityWeight, CashPriority.Kind.retirement.bandGradient),
         ("Bonds", recommendation.bondWeight, FundPalette.bonds),
         ("Other", recommendation.otherWeight, PlanPalette.minimum)]
            .filter { $0.1 > 0 }
            .map { SegmentedBand.Segment(label: $0.0, value: FundCopy.pct1($0.1), weight: $0.1, colors: $0.2) }
    }
}

enum FundPalette {
    /// The Plan allocation ring's bond grey, as a band gradient.
    static let bonds = [Color(hex: 0x767A8C), PlanPalette.bonds, Color(hex: 0x3E404C)]
}
