import SwiftUI

/// Balance-first Overview: saved retirement balance, an edge-to-edge illustrative projection,
/// planned contributions, then the next step — the only card on the page.
struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    /// 0…1 playhead on the projection while scrubbing.
    @State private var scrub: Double?
    @State private var isScrolled = !ScreenHeaderScroll.isTrackable

    private var profile: Profile { store.displayProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                balanceSummary
                projection
                contributions
                    .padding(.horizontal, Space.xl)
                    .padding(.top, Space.m)
                nextStep
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.xl)
                supportingDetails
                    .padding(.horizontal, Space.xl)
                    .padding(.bottom, Space.xl)
                footer
            }
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .tracksScrolled($isScrolled)
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(isScrolled: isScrolled) {
                ProfileSwitcher()
            } trailing: {
                HeaderAvatarButton()
            }
        }
        .animation(Motion.reveal, value: profile.id)
    }

    // MARK: Sections

    /// Whole years from today to the scrubbed point, or nil when not scrubbing.
    private var scrubYears: Int? {
        scrub.map { Int(($0 * Double(profile.yearsToRetirement)).rounded()) }
    }

    private var balanceSummary: some View {
        let years = scrubYears
        return VStack(alignment: .leading, spacing: Space.s) {
            Text(years.map { "Projected at age \(profile.age + $0)" } ?? "Retirement savings")
                .font(.geist(18, .medium, relativeTo: .headline))
                .foregroundStyle(years == nil ? Palette.textPrimary : Palette.accent)
                .contentTransition(.opacity)
            BalanceAmount(cents: years.map { OverviewCopy.projectedCents(for: profile, years: $0) }
                          ?? profile.retirementBalanceCents)
            Text(years.map { "\(Disclosure.illustrative) · \(String(OverviewCopy.asOfYear + $0))" }
                 ?? "As of \(OverviewCopy.asOf)")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .contentTransition(.opacity)
        }
        .animation(Motion.select, value: years)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
    }

    /// "To age 67" link (opens Explore), then the full-width chart — tap or press-and-drag to scrub.
    private var projection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                store.tab = .explore
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                    Text("To age \(profile.retirementAge)")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.geist(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassCapsule(tint: Palette.accent, interactive: false)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, Space.xl)
            .accessibilityHint("Opens Explore")

            ProjectionChart(adaptive: OverviewCopy.curve(for: profile),
                            adaptiveName: "Retirement savings",
                            selection: $scrub,
                            selectionSteps: profile.yearsToRetirement)
                .frame(height: 204)
                .accessibilityLabel("\(Disclosure.illustrative) from today to age \(profile.retirementAge)")
                .accessibilityValue(scrubYears.map { "Age \(profile.age + $0), \(Money.whole(OverviewCopy.projectedCents(for: profile, years: $0)))" } ?? "")
                .accessibilityAdjustableAction { direction in
                    let n = Double(max(profile.yearsToRetirement, 1))
                    let current = (scrub ?? 0) * n
                    scrub = min(max((current + (direction == .increment ? 1 : -1)) / n, 0), 1)
                }

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
            .accessibilityHidden(true)
        }
        .onChange(of: profile.id) { scrub = nil }
        #if DEBUG
        // `-scrub 0.5` opens with the playhead placed, for screenshots.
        .onAppear {
            if UserDefaults.standard.object(forKey: "scrub") != nil {
                scrub = UserDefaults.standard.double(forKey: "scrub")
            }
        }
        #endif
    }

    private var contributions: some View {
        Button {
            store.tab = .plan
        } label: {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.m) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 1, dim: 0.8))
        .accessibilityHint("Opens your plan")
    }

    private var nextStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
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
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, Space.l)
                .frame(minHeight: 40)
                .glassCapsule(tint: Palette.accent)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, Space.xs)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Palette.accentStrong)
    }

    private var supportingDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Emergency savings")
                        .font(.geist(16, .regular, relativeTo: .body))
                        .foregroundStyle(Palette.textPrimary)
                    (Text(Money.whole(profile.emergencyCashCents)).font(.numeral(12, .medium, relativeTo: .caption))
                     + Text(" set aside").font(.geist(12, .regular, relativeTo: .caption)))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: Space.m)
                MonthsLabel(months: profile.emergencyMonths, size: 18)
            }
            .frame(minHeight: 58)
            .padding(.bottom, Space.s)
            .accessibilityElement(children: .combine)

            Hairline()

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
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            Hairline()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Button {
                store.tab = .plan
            } label: {
                Label("View your plan", systemImage: "list.bullet.rectangle.portrait")
            }
            .buttonStyle(PrimaryButtonStyle())

            LiveStatusRow()
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

/// "$35,000" in Geist with raised cents, per the Overview design.
private struct BalanceAmount: View {
    let cents: Int64

    var body: some View {
        let parts = Money.split(cents)
        HStack(alignment: .top, spacing: 0) {
            Text(parts.dollars)
                .font(.numeral(42, .medium, relativeTo: .largeTitle))
                .tracking(-2.4)
            Text(".\(parts.cents)")
                .font(.numeral(20, .regular, relativeTo: .title2))
                .tracking(-0.8)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 5)
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
                .font(.numeral(25, .medium, relativeTo: .title2))
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

/// "1 month" / "6 months" with a Medium count and Regular unit.
struct MonthsLabel: View {
    let months: Double
    var size: CGFloat = 18
    var color: Color = Palette.textPrimary

    var body: some View {
        (Text(OverviewCopy.monthsCount(months)).font(.numeral(size, .medium, relativeTo: .headline))
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

    /// Balance `years` from today: the engine's adaptive projection when an evaluation is loaded.
    /// Otherwise an illustrative balance read off the drawn curve so the number matches
    /// where the playhead sits. The curve runs from today's balance to a nominal future value at
    /// retirement: monthly compounding of the saved balance plus employee and employer
    /// contributions at the allocation-weighted ModelAssumptions return. Display only.
    static func projectedCents(for profile: Profile, years: Int) -> Int64 {
        if let balance = profile.evaluation?.projections.adaptive.retirementBalance(atYear: years) {
            return years == 0 ? balance : (balance + 5_000) / 10_000 * 10_000
        }
        let n = max(profile.yearsToRetirement, 1)
        let a = ModelAssumptions.illustrative
        let annual = profile.equityWeight * a.annualEquityReturn + (1 - profile.equityWeight) * a.annualBondReturn
        let r = annual / 12, months = Double(n * 12)
        let start = Double(profile.retirementBalanceCents)
        let monthly = Double(profile.employeeMonthlyCents + profile.employerMonthlyCents)
        let growth = pow(1 + r, months)
        let end = start * growth + (r > 0 ? monthly * (growth - 1) / r : monthly * months)

        let curve = IllustrativeProjection.overview()
        let c0 = curve.first ?? 0, c1 = curve.last ?? 1
        let t = (ProjectionChart.sample(curve, at: Double(years) / Double(n)) - c0) / max(c1 - c0, 0.0001)
        let value = start + (end - start) * t
        return years == 0 ? profile.retirementBalanceCents : Int64((value / 10_000).rounded()) * 10_000
    }

    /// The engine's yearly adaptive balances, normalised, or the schematic curve without an evaluation.
    static func curve(for profile: Profile) -> [Double] {
        guard let adaptive = profile.evaluation?.projections.adaptive else { return IllustrativeProjection.overview() }
        let balances = adaptive.yearlyRetirementBalances(years: profile.yearsToRetirement)
        let top = Double(max(balances.max() ?? 1, 1))
        return balances.count > 1 ? balances.map { Double($0) / top } : IllustrativeProjection.overview()
    }

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
        // Written as typed loops: the compact closure form overwhelmed the type checker.
        let n = knots.count
        var d: [Double] = []
        for k in 0..<(n - 1) {
            let rise: Double = knots[k + 1].y - knots[k].y
            let run: Double = knots[k + 1].x - knots[k].x
            d.append(rise / run)
        }
        var m: [Double] = [d[0]]
        for k in 1..<(n - 1) {
            let sameDirection: Bool = d[k - 1] * d[k] > 0
            m.append(sameDirection ? (d[k - 1] + d[k]) / 2 : 0)
        }
        m.append(d[n - 2])
        for k in 0..<(n - 1) where d[k] != 0 {
            let a: Double = m[k] / d[k]
            let b: Double = m[k + 1] / d[k]
            let h: Double = a * a + b * b
            if h > 9 {
                let limit: Double = 3 / h.squareRoot() * d[k]
                m[k] = a * limit
                m[k + 1] = b * limit
            }
        }
        var values: [Double] = []
        for i in 0..<count {
            let x: Double = Double(i) / Double(count - 1)
            let k: Int = min(knots.lastIndex { $0.x <= x } ?? 0, n - 2)
            let a = knots[k]
            let b = knots[k + 1]
            let h: Double = b.x - a.x
            let t: Double = (x - a.x) / h
            let t2: Double = t * t
            let t3: Double = t2 * t
            let h00: Double = 2 * t3 - 3 * t2 + 1
            let h10: Double = t3 - 2 * t2 + t
            let h01: Double = -2 * t3 + 3 * t2
            let h11: Double = t3 - t2
            let value: Double = h00 * a.y + h10 * h * m[k] + h01 * b.y + h11 * h * m[k + 1]
            values.append(value)
        }
        return values
    }
}

#Preview {
    OverviewView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
