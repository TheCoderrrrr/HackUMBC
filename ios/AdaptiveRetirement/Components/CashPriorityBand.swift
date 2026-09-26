import SwiftUI

extension CashPriority.Kind {
    /// Top → bottom gradient for the band segment.
    var bandGradient: [Color] {
        switch self {
        case .retirement: [Color(hex: 0x655CBA), Color(hex: 0x504990), Color(hex: 0x393350)]
        case .debt: [Color(hex: 0x9F6548), Color(hex: 0x83543D), Color(hex: 0x573D33)]
        case .emergency: [Color(hex: 0x4F8C79), Color(hex: 0x3D6B5E), Color(hex: 0x2C4640)]
        case .remaining: [Color(hex: 0x5A5C68), Color(hex: 0x454650), Color(hex: 0x30313A)]
        }
    }

    /// Marker and amount colour, matched to the segment.
    var accent: Color {
        switch self {
        case .retirement: Palette.lavender
        case .debt: Color(hex: 0xE3AC8D)
        case .emergency: Palette.positive
        case .remaining: Palette.textPrimary
        }
    }
}

/// Monthly cash priorities: a 40 pt proportional band with gradient, grain and fading ribs.
/// Only funded categories get a slice; $0 rows are represented in the list, not the graphic.
struct CashPriorityBand: View {
    let priorities: [CashPriority]
    var height: CGFloat = 40
    var gap: CGFloat = 4

    private var funded: [CashPriority] { priorities.filter { $0.amountCents > 0 } }
    private var total: Int64 { funded.reduce(0) { $0 + $1.amountCents } }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - gap * CGFloat(max(funded.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(funded) { item in
                    segment(item)
                        .frame(width: max(available * share(item), 0))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    func share(_ item: CashPriority) -> Double {
        total > 0 ? Double(item.amountCents) / Double(total) : 0
    }

    /// Rounded one-decimal share, e.g. "22.1%".
    func shareLabel(_ item: CashPriority) -> String {
        (share(item)).formatted(.percent.precision(.fractionLength(1)))
    }

    private func segment(_ item: CashPriority) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape
                .fill(LinearGradient(colors: item.kind.bandGradient, startPoint: .top, endPoint: .bottom))
                .fillGrain()
            Ribs()
                .stroke(LinearGradient(stops: [
                    .init(color: .white.opacity(0.16), location: 0),
                    .init(color: .white.opacity(0.025), location: 0.7),
                    .init(color: .white.opacity(0), location: 1)
                ], startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
                .clipShape(shape)
            shape.strokeBorder(Color.white.opacity(0.13), lineWidth: 0.6)
            Text(shareLabel(item))
                .font(.geist(13, .semibold, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0xFAF9FF))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
        }
    }

    private var accessibilitySummary: String {
        funded.map { "\($0.title) \(shareLabel($0))" }.joined(separator: ", ")
    }
}

/// Vertical hairlines every 4 pt.
private struct Ribs: Shape {
    var spacing: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        Path { path in
            var x = rect.minX + 0.25
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += spacing
            }
        }
    }
}

/// A category row under the band: 6 pt marker (hollow when unfunded), label, tinted amount.
struct CashPriorityRow: View {
    let priority: CashPriority
    /// Overrides the fixture title (e.g. "Retirement take-home cost").
    var title: String? = nil

    private var funded: Bool { priority.amountCents > 0 }

    var body: some View {
        HStack(spacing: Space.s) {
            Circle()
                .strokeBorder(funded ? .clear : Palette.textCaption, lineWidth: 1)
                .background(Circle().fill(funded ? priority.kind.accent : .clear))
                .frame(width: 6, height: 6)
            Text(title ?? priority.title)
                .font(.geist(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.m)
            Text(Money.exact(priority.amountCents))
                .font(.geist(16, .semibold, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(funded ? priority.kind.accent : Palette.textSecondary)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 12) {
        CashPriorityBand(priorities: Profile.morgan.cashPriorities)
        ForEach(Profile.morgan.cashPriorities) { CashPriorityRow(priority: $0) }
    }
    .padding(24)
    .background(Palette.page)
}
