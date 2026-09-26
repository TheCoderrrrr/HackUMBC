import SwiftUI

/// Balance-first Overview: saved retirement balance, an edge-to-edge illustrative projection,
/// planned contributions, then the next step as an open section.
struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    private var profile: Profile { store.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                balanceSummary
                projection
                VStack(spacing: Space.m) {
                    contributions
                    nextStep
                    supportingDetails
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xl)
                footer
            }
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .background(AmbientGlow())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader {
                ProfileSwitcher()
            } trailing: {
                HeaderAvatarButton()
            }
        }
        .animation(Motion.reveal, value: profile.id)
    }

    // MARK: Sections

    private var balanceSummary: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Retirement savings")
                .font(.geist(18, .medium, relativeTo: .headline))
                .foregroundStyle(Palette.textPrimary)
            BalanceAmount(cents: profile.retirementBalanceCents)
            Text("As of \(OverviewCopy.asOf)")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
    }

    /// "To age 67" link, the full-width chart, and its horizon labels. The whole block opens Explore.
    private var projection: some View {
        Button {
            store.tab = .explore
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                    Text("To age \(profile.retirementAge)")
                        .font(.geist(13, .medium, relativeTo: .footnote))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Palette.lavender)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassCapsule(tint: Palette.lavender, interactive: false)
                .frame(height: 44)
                    .padding(.horizontal, Space.xl)

                ProjectionChart(adaptive: IllustrativeProjection.overview(), adaptiveName: "Retirement savings")
                    .frame(height: 204)

                HStack {
                    Text("Today")
                    Spacer()
                    Text(verbatim: "\(OverviewCopy.retirementYear(for: profile)) · Age \(profile.retirementAge)")
                }
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.s)
                .frame(minHeight: 44, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 1, dim: 0.8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Disclosure.illustrative) from today to age \(profile.retirementAge)")
        .accessibilityHint("Opens Explore")
    }

    private var contributions: some View {
        Button {
            store.tab = .plan
        } label: {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.m) {
                    IconBadge(systemName: "arrow.down.to.line.compact")
                    Text("Planned monthly contributions")
                        .font(.geist(17, .medium, relativeTo: .headline))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.textCaption)
                }
                HStack(alignment: .top, spacing: Space.xl) {
                    ContributionColumn(title: "You", symbol: "person.fill",
                                       cents: profile.employeeMonthlyCents,
                                       caption: "\(OverviewCopy.percent(profile.adaptiveEmployeeRate)) of salary")
                    ContributionColumn(title: "Employer", symbol: "building.2.fill",
                                       cents: profile.employerMonthlyCents,
                                       caption: profile.matchCaptured ? "Full match" : "Partial match")
                }
            }
            .padding(20)
            .contentShape(Rectangle())
            .glassCard()
        }
        .buttonStyle(PressableStyle(scale: 1, dim: 0.8))
        .accessibilityHint("Opens your plan")
    }

    private var nextStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                IconBadge(systemName: "flag.checkered", tint: Palette.peach)
                Text("Your next step")
                    .font(.geist(18, .medium, relativeTo: .headline))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.bottom, Space.m)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(OverviewCopy.nextStepHeadline(for: profile))
                    .font(.geist(16, .medium, relativeTo: .body))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.textPrimary)
                OverviewCopy.nextStepDetail(for: profile)
                    .font(.geist(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, Space.s)

            Button {
                store.sheet = .explanation
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Why this plan?")
                        .font(.geist(15, .medium, relativeTo: .body))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Palette.lavender)
                .padding(.horizontal, Space.l)
                .frame(minHeight: 40)
                .glassCapsule(tint: Palette.lavender)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, Space.xs)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Palette.indigo)
    }

    private var supportingDetails: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.m) {
                IconBadge(systemName: "umbrella.fill", tint: Palette.positive)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Emergency savings")
                        .font(.geist(16, .regular, relativeTo: .body))
                        .foregroundStyle(Palette.textPrimary)
                    (Text(Money.whole(profile.emergencyCashCents)).font(.geist(12, .medium, relativeTo: .caption))
                     + Text(" set aside").font(.geist(12, .regular, relativeTo: .caption)))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: Space.m)
                MonthsLabel(months: profile.emergencyMonths, size: 18)
            }
            .frame(minHeight: 58)
            .accessibilityElement(children: .combine)

            Button {
                store.sheet = .snapshot
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                    Text("Financial snapshot")
                        .font(.geist(15, .medium, relativeTo: .subheadline))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Palette.lavender)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Space.l)
        .glassCard()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Button {
                store.tab = .plan
            } label: {
                Label("View your plan", systemImage: "list.bullet.rectangle.portrait")
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                DataModeBadge(mode: store.dataMode)
                Spacer(minLength: 0)
            }
            Text(Disclosure.fictional)
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.xl)
    }
}

// MARK: - Pieces

/// "Morgan ⌄" — opens the profile picker.
private struct ProfileSwitcher: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            store.sheet = .profilePicker
        } label: {
            HStack(spacing: Space.s) {
                Text(store.profile.name)
                    .font(.geist(18, .medium, relativeTo: .headline))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(store.profile.name), switch profile")
    }
}

/// "$35,000" SemiBold with raised Medium cents, per the Overview design.
private struct BalanceAmount: View {
    let cents: Int64

    var body: some View {
        let parts = Money.split(cents)
        HStack(alignment: .top, spacing: 0) {
            Text(parts.dollars)
                .font(.geist(46, .semibold, relativeTo: .largeTitle))
                .tracking(-1.38)
            Text(".\(parts.cents)")
                .font(.geist(24, .medium, relativeTo: .title2))
                .tracking(-0.48)
                .padding(.top, 3)
        }
        .monospacedDigit()
        .foregroundStyle(Palette.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Money.exact(cents))
    }
}

private struct ContributionColumn: View {
    let title: String
    let symbol: String
    let cents: Int64
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label {
                Text(title).font(.geist(13, .regular, relativeTo: .footnote))
            } icon: {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Palette.textSecondary)
            Text(Money.exact(cents))
                .font(.geist(25, .semibold, relativeTo: .title2))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "1 month" / "6 months" with a SemiBold count and Medium unit.
struct MonthsLabel: View {
    let months: Double
    var size: CGFloat = 18
    var color: Color = Palette.textPrimary

    var body: some View {
        (Text(OverviewCopy.monthsCount(months)).font(.geist(size, .semibold, relativeTo: .headline))
         + Text(months == 1 ? " month" : " months").font(.geist(size, .medium, relativeTo: .headline)))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

// MARK: - Copy and schematic data

/// Display copy derived from the saved demo values. No financial policy lives here.
enum OverviewCopy {
    /// Fixture date for the saved demo calculation (BACKEND.md §12).
    static let asOf = "Sep 26, 2026"
    static let asOfYear = 2026

    static func retirementYear(for profile: Profile) -> Int { asOfYear + profile.yearsToRetirement }

    static func percent(_ rate: Double) -> String {
        rate.formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func monthsCount(_ months: Double) -> String {
        months.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func nextStepHeadline(for profile: Profile) -> String {
        switch profile.id {
        case "morgan": "Keep the match. Tackle the debt."
        case "casey": "Stay the course into retirement."
        default: "Keep saving at your current rate."
        }
    }

    /// Detail sentence with the key amount emphasised.
    static func nextStepDetail(for profile: Profile) -> Text {
        if let amount = profile.primaryActionAmountCents, let debt = profile.debts.first {
            return Text(Money.exact(amount)).font(.geist(13, .medium, relativeTo: .footnote))
                + Text(" extra toward your \(debt.name.lowercased()) each month.")
        }
        return Text(profile.primaryActionDetail)
    }
}

extension IllustrativeProjection {
    /// Overview's single adaptive series: flat near today, rising, easing toward 67.
    /// Schematic shape only — traced from the Figma contour, not engine output.
    static func overview(count: Int = 64) -> [Double] {
        let knots: [(x: Double, y: Double)] = [
            (0, 0.026), (0.223, 0.079), (0.45, 0.376), (0.691, 0.72), (1, 1)
        ]
        // Monotone cubic (Fritsch–Carlson) through the knots: smooth, no overshoot.
        let n = knots.count
        let d = (0..<(n - 1)).map { (knots[$0 + 1].y - knots[$0].y) / (knots[$0 + 1].x - knots[$0].x) }
        var m = [d[0]] + (1..<(n - 1)).map { d[$0 - 1] * d[$0] <= 0 ? 0 : (d[$0 - 1] + d[$0]) / 2 } + [d[n - 2]]
        for k in 0..<(n - 1) where d[k] != 0 {
            let a = m[k] / d[k], b = m[k + 1] / d[k], h = a * a + b * b
            if h > 9 { m[k] = 3 * a / h.squareRoot() * d[k]; m[k + 1] = 3 * b / h.squareRoot() * d[k] }
        }
        return (0..<count).map { i in
            let x = Double(i) / Double(count - 1)
            let k = min(knots.lastIndex { $0.x <= x } ?? 0, n - 2)
            let a = knots[k], b = knots[k + 1], h = b.x - a.x
            let t = (x - a.x) / h, t2 = t * t, t3 = t2 * t
            return (2 * t3 - 3 * t2 + 1) * a.y + (t3 - 2 * t2 + t) * h * m[k]
                + (-2 * t3 + 3 * t2) * b.y + (t3 - t2) * h * m[k + 1]
        }
    }
}

#Preview {
    OverviewView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
