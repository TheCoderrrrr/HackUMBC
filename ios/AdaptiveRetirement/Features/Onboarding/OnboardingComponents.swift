import SwiftUI

// MARK: - Setup tokens

enum SetupStyle {
    /// Setup screens use a 24 pt gutter (345 pt content at the 393 pt reference width).
    static let gutter: CGFloat = 24
    /// Neutral disc behind the avatar and topic icons (iOS bordered control on the frosted surface).
    static let disc = Color(hex: 0x28292F)
    static let divider = Color(hex: 0x2D2E35)
    /// Secondary text sits directly on the moving field (no frost), so it runs brighter.
    static let secondaryText = Color.white.opacity(0.74)

    static let heading = Font.geist(26, .bold, relativeTo: .title)
    static let instruction = Font.geist(16, .regular, relativeTo: .body)
    static let navTitle = Font.geist(17, .semibold, relativeTo: .headline)
    static let progress = Font.geist(13, .medium, relativeTo: .footnote)
    static let rowTitle = Font.geist(17, .semibold, relativeTo: .headline)
    static let rowDetail = Font.geist(13, .regular, relativeTo: .footnote)
    static let secondaryAction = Font.geist(15, .medium, relativeTo: .subheadline)
}

// MARK: - Focus presentation

extension Focus {
    var setupTitle: String {
        switch self {
        case .debt: "Pay down debt"
        case .cash: "Build a buffer"
        case .retirement: "Save for retirement"
        }
    }

    var setupSymbol: String {
        switch self {
        case .debt: "creditcard"
        case .cash: "banknote"
        case .retirement: "chart.line.uptrend.xyaxis"
        }
    }

    func setupDetail(for profile: Profile) -> String {
        switch self {
        case .debt:
            guard let debt = profile.debts.first else { return "No debt" }
            return "\(debt.name) · \(Int((debt.apr * 100).rounded()))% APR"
        case .cash:
            return "Emergency cash · \(Money.whole(profile.emergencyCashCents))"
        case .retirement:
            return profile.matchCaptured ? "Employer match available" : "Retirement contributions"
        }
    }

    var resultHeading: String {
        switch self {
        case .debt: "Your next step."
        case .cash: "Your cash buffer."
        case .retirement: "Your retirement."
        }
    }

    /// One amount and brief context from the saved Balanced plan (display only).
    func result(for profile: Profile) -> (amount: String, unit: String, context: String) {
        switch self {
        case .debt:
            let extra = profile.debts.first?.extraCents ?? 0
            let minimum = profile.debts.first?.minimumCents ?? 0
            return (Money.exact(extra),
                    "Extra to your credit card each month",
                    "\(Money.exact(extra + minimum)) total, including the minimum.")
        case .cash:
            let months = Int(profile.emergencyMonths.rounded())
            return (Money.whole(profile.emergencyCashCents),
                    "Your emergency cash",
                    "\(months) month\(months == 1 ? "" : "s") covered · Next target: \(profile.fullTargetMonths) months")
        case .retirement:
            return (Money.whole(profile.employeeMonthlyCents + profile.employerMonthlyCents),
                    "Into retirement each month",
                    "\(Money.whole(profile.employeeMonthlyCents)) from you + \(Money.whole(profile.employerMonthlyCents)) employer match")
        }
    }
}

// MARK: - Continuity slots

/// Named layout slots that the persistent avatar / selected icon fly between.
struct SetupSlotKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports this view's bounds as a continuity slot.
    func setupSlot(_ id: String) -> some View {
        anchorPreference(key: SetupSlotKey.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Discs

/// Profile identity on setup: a neutral disc with the initial. Drawn once at 112 pt and scaled.
struct SetupAvatar: View {
    let profile: Profile
    static let baseSize: CGFloat = 112

    var body: some View {
        Circle()
            .fill(SetupStyle.disc)
            .overlay {
                Text(profile.initials)
                    .font(.custom(GeistWeight.regular.postScriptName, fixedSize: Self.baseSize * 0.4))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: Self.baseSize, height: Self.baseSize)
    }
}

/// Topic icon disc. Drawn at 80 pt and scaled so the glyph morphs smoothly.
struct TopicDisc: View {
    let symbol: String
    static let baseSize: CGFloat = 80

    var body: some View {
        Circle()
            .fill(SetupStyle.disc)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Palette.lavender)
            }
            .frame(width: Self.baseSize, height: Self.baseSize)
    }
}

extension View {
    /// Places a fixed-size drawing into `rect` by scaling from its base size.
    func place(in rect: CGRect, baseSize: CGFloat) -> some View {
        scaleEffect(rect.width / baseSize)
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Header

/// Top-aligned step header: small icon disc, heading, and a secondary line.
struct SetupHeader<Icon: View>: View {
    let heading: String
    let subtitle: Text
    @ViewBuilder let icon: Icon

    static var iconSize: CGFloat { 64 }

    var body: some View {
        VStack(spacing: 0) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)

            Text(heading)
                .font(SetupStyle.heading)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.l)

            subtitle
                .font(SetupStyle.instruction)
                .foregroundStyle(SetupStyle.secondaryText)
                .lineSpacing(2)
                .padding(.top, Space.s)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}

/// A topic disc drawn at header size.
struct HeaderGlyph: View {
    let symbol: String

    var body: some View {
        TopicDisc(symbol: symbol)
            .scaleEffect(SetupHeader<EmptyView>.iconSize / TopicDisc.baseSize)
    }
}

/// Charcoal capsule for a step's key value, like a code-entry pill.
struct SetupPill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, Space.xxl)
            .frame(minHeight: 72)
            .background(SetupStyle.disc, in: Capsule())
    }
}
