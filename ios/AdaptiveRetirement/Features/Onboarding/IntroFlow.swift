import SwiftUI

/// Splash → intro → setup. Five slides that make the case before the walkthrough:
/// what a target-date fund knows, what it misses, what that costs this profile,
/// and what Adaptive does about it. Every dollar figure comes from the engine's
/// current (autopilot) and adaptive projections; without an evaluation the slides
/// fall back to profile facts and schematic curves. Slides only move when asked.
enum IntroSlide: Int, CaseIterable, Comparable {
    case autopilot, blindSpots, example, adaptive, howItWorks
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }

    var next: IntroSlide? { IntroSlide(rawValue: rawValue + 1) }
    var previous: IntroSlide? { IntroSlide(rawValue: rawValue - 1) }
}

struct IntroFlow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slide: IntroSlide { store.introSlide }
    private var profile: Profile { store.displayProfile }

    /// Progress bar plus the gap above slide content.
    static let chromeHeight: CGFloat = 44 + Space.s + Space.xl

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                // The opening chart runs up behind the progress bar and fades into the page.
                if slide == .autopilot {
                    GlidePathBackdrop(plotTop: topInset + Self.chromeHeight)
                        .frame(height: topInset + Self.chromeHeight + AutopilotSlide.chartHeight)
                        .offset(y: -topInset)
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(Motion.select))
                }

                VStack(spacing: 0) {
                    progressBar

                    ZStack(alignment: .top) {
                        slideContent
                            .id(slide)
                            .transition(transition)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .gesture(swipe)
                    .padding(.top, Space.xl)

                    actions
                }
                .padding(.horizontal, SetupStyle.gutter)
            }
        }
        .sensoryFeedback(trigger: slide) { old, new in
            .impact(weight: new > old ? .medium : .light)
        }
    }

    // MARK: Slides

    @ViewBuilder
    private var slideContent: some View {
        let facts = IntroFacts(profile: profile)
        switch slide {
        case .autopilot: AutopilotSlide()
        case .blindSpots: BlindSpotsSlide()
        case .example: ExampleSlide(profile: profile, facts: facts)
        case .adaptive: AdaptiveSlide(profile: profile, facts: facts)
        case .howItWorks: HowItWorksSlide()
        }
    }

    private var transition: AnyTransition {
        let reveal: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
        return .asymmetric(insertion: reveal.animation(Motion.reveal.delay(reduceMotion ? 0 : 0.12)),
                           removal: .opacity.animation(Motion.select))
    }

    // MARK: Progress

    /// One segment per slide; segments up to the current slide are lit.
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(IntroSlide.allCases, id: \.self) { item in
                Capsule()
                    .fill(item <= slide ? Palette.textPrimary : Color.white.opacity(0.18))
                    .frame(height: 3)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Intro")
        .accessibilityValue("\(slide.rawValue + 1) of \(IntroSlide.allCases.count)")
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Space.s) {
            Button(action: advance) {
                Text(slide.next == nil ? "Try it with \(store.profile.name)" : "Next")
                    .contentTransition(.opacity)
            }
            .buttonStyle(SetupPrimaryButtonStyle())

            // Space stays reserved so the primary button doesn't jump on the first slide.
            Button(action: back) {
                Text("Back")
                    .font(SetupStyle.secondaryAction)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .opacity(slide.previous == nil ? 0 : 1)
            .disabled(slide.previous == nil)
        }
        .padding(.bottom, 15)
    }

    // MARK: Navigation

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 40, abs(dx) > abs(value.translation.height) else { return }
                if dx < 0 {
                    if let next = slide.next { go(to: next) }
                } else {
                    back()
                }
            }
    }

    private func advance() {
        if let next = slide.next { go(to: next) } else { finish() }
    }

    private func back() {
        guard let previous = slide.previous else { return }
        go(to: previous)
    }

    private func go(to next: IntroSlide) {
        withAnimation(Motion.respecting(reduceMotion, Motion.smart)) {
            store.introSlide = next
        }
    }

    private func finish() {
        withAnimation(Motion.respecting(reduceMotion, Motion.handoff)) {
            store.introSlide = .howItWorks
            store.onboardingStep = .profile
            store.phase = .onboarding
        }
    }
}

// MARK: - Facts

/// Autopilot vs Adaptive, read straight off the engine's projections. Nil without an evaluation.
struct IntroFacts {
    let currentFinal: Int64?
    let adaptiveFinal: Int64?
    let currentDebtFreeMonth: Int?
    let adaptiveDebtFreeMonth: Int?
    let currentInterest: Int64?
    let adaptiveInterest: Int64?
    /// Yearly balances normalised to the larger series, or schematic curves without an evaluation.
    let currentCurve: [Double]
    let adaptiveCurve: [Double]
    let isIllustrative: Bool

    init(profile: Profile) {
        let current = profile.evaluation?.projections.current
        let adaptive = profile.evaluation?.projections.adaptive
        currentFinal = current?.retirementBalanceNominalCents
        adaptiveFinal = adaptive?.retirementBalanceNominalCents
        currentDebtFreeMonth = current?.debtFreeMonth
        adaptiveDebtFreeMonth = adaptive?.debtFreeMonth
        currentInterest = current?.cumulativeDebtInterestCents
        adaptiveInterest = adaptive?.cumulativeDebtInterestCents

        let years = profile.yearsToRetirement
        let c = current?.yearlyRetirementBalances(years: years) ?? []
        let a = adaptive?.yearlyRetirementBalances(years: years) ?? []
        if c.count > 1, a.count > 1 {
            let top = Double(max(c.max() ?? 1, a.max() ?? 1, 1))
            currentCurve = c.map { Double($0) / top }
            adaptiveCurve = a.map { Double($0) / top }
            isIllustrative = false
        } else {
            currentCurve = IllustrativeProjection.current()
            adaptiveCurve = IllustrativeProjection.adaptive()
            isIllustrative = true
        }
    }

    /// How much more Adaptive ends with; nil when there's nothing meaningful to claim.
    var gain: Int64? {
        guard let currentFinal, let adaptiveFinal else { return nil }
        let gain = adaptiveFinal - currentFinal
        return gain >= 100_000 ? gain : nil
    }

    var interestSaved: Int64? {
        guard let currentInterest, let adaptiveInterest else { return nil }
        let saved = currentInterest - adaptiveInterest
        return saved >= 10_000 ? saved : nil
    }

    static func duration(months: Int) -> String {
        if months < 24 { return "\(months) month\(months == 1 ? "" : "s")" }
        return "\(Int((Double(months) / 12).rounded())) years"
    }
}

// MARK: - 1 · Autopilot

/// The glide path is drawn by `IntroFlow` behind the progress bar; this slide reserves
/// its space and sets the copy underneath.
private struct AutopilotSlide: View {
    static let chartHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.chartHeight)

            HStack {
                Text("Age 25 · 90% stocks")
                Spacer(minLength: 0)
                Text("Age 65 · 50%")
            }
            .font(.geist(12, .regular, relativeTo: .caption))
            .foregroundStyle(Palette.textCaption)
            .padding(.top, Space.s)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Illustrative glide path: 90% stocks at age 25, easing to 50% at 65.")

            VStack(spacing: Space.s) {
                Text("Your 401(k) runs on one number.")
                    .font(SetupStyle.heading)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Target-date funds are the default in many\nplans. They only know when you'll retire.")
                    .font(SetupStyle.instruction)
                    .foregroundStyle(SetupStyle.secondaryText)
                    .lineSpacing(2)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.xl)

            Text("As retirement nears, it shifts from stocks to bonds.\nNothing else about you changes the plan.")
                .font(SetupStyle.rowDetail)
                .foregroundStyle(SetupStyle.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, Space.l)

            Spacer(minLength: 0)
        }
    }
}

/// Full-bleed stocks vs bonds from age 25 to 65 along the illustrative glide path.
/// 100% sits at `plotTop`; the bonds band continues above it and fades into the page,
/// so the chart dissolves into the status bar and progress indicator. Sweeps in left to right.
private struct GlidePathBackdrop: View {
    let plotTop: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private static let startAge = 25
    private static let endAge = 65
    private static let green = Color(hex: 0x86DB8F)
    private let glide = ModelAssumptions.illustrative.glidePath

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let equity = samples()
            let fadeEnd = min(max(plotTop / max(size.height, 1), 0.05), 0.95)
            ZStack(alignment: .topLeading) {
                area(equity, in: size, top: true)
                    .fill(Palette.blue.opacity(0.34))
                area(equity, in: size, top: false)
                    .fill(LinearGradient(colors: [Self.green.opacity(0.55), Self.green.opacity(0.18)],
                                         startPoint: .top, endPoint: .bottom))
                    .fillGrain()
                ForEach([0.25, 0.5, 0.75], id: \.self) { level in
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .offset(y: y(level, size))
                }
                line(equity, in: size)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                label("Bonds", color: Palette.blue)
                    .padding(.horizontal, SetupStyle.gutter)
                    .frame(width: size.width, alignment: .trailing)
                    .offset(y: plotTop + Space.m)
                label("Stocks", color: Palette.accent)
                    .padding(.horizontal, SetupStyle.gutter)
                    .padding(.bottom, Space.l)
                    .frame(width: size.width, height: size.height, alignment: .bottomLeading)
            }
            .mask(alignment: .leading) {
                Rectangle().frame(width: revealed ? size.width : 0)
            }
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black.opacity(0.35), location: fadeEnd * 0.6),
                                       .init(color: .black, location: fadeEnd)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 1.4).delay(0.2)) {
                revealed = true
            }
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.geist(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.textPrimary.opacity(0.9))
        }
    }

    private func y(_ value: Double, _ size: CGSize) -> CGFloat {
        plotTop + (size.height - plotTop) * CGFloat(1 - value)
    }

    /// Equity weight at each age, interpolated between glide-path anchors.
    private func samples() -> [Double] {
        let anchors = glide.sorted { $0.yearsToRetirement > $1.yearsToRetirement }
        return (Self.startAge...Self.endAge).map { age in
            let years = Self.endAge - age
            guard let first = anchors.first, years < first.yearsToRetirement else { return anchors.first?.equityWeight ?? 0.9 }
            for (hi, lo) in zip(anchors, anchors.dropFirst()) where years <= hi.yearsToRetirement && years >= lo.yearsToRetirement {
                let span = Double(hi.yearsToRetirement - lo.yearsToRetirement)
                let t = span > 0 ? Double(hi.yearsToRetirement - years) / span : 0
                return hi.equityWeight + (lo.equityWeight - hi.equityWeight) * t
            }
            return anchors.last?.equityWeight ?? 0.5
        }
    }

    private func line(_ values: [Double], in size: CGSize) -> Path {
        Path { p in
            for i in values.indices {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)), y: y(values[i], size))
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
    }

    /// The band above (bonds, up to the top edge) or below (stocks) the equity line.
    private func area(_ values: [Double], in size: CGSize, top: Bool) -> Path {
        var p = line(values, in: size)
        let edge: CGFloat = top ? 0 : size.height
        p.addLine(to: CGPoint(x: size.width, y: edge))
        p.addLine(to: CGPoint(x: 0, y: edge))
        p.closeSubpath()
        return p
    }
}

// MARK: - 2 · Blind spots

private struct BlindSpotsSlide: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    private let rows: [(symbol: String, title: String, detail: String)] = [
        ("creditcard", "High-interest debt", "A 25% card costs more than the fund earns"),
        ("banknote", "Emergency savings", "Without a buffer, a surprise bill becomes debt"),
        ("building.columns", "Employer match", "Save too little and free money is left behind")
    ]

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(
                heading: "It can't see the rest.",
                subtitle: Text("Your paycheck has more than one job.\nThe fund only knows about one of them.")
            ) {
                HeaderGlyph(symbol: "eye.slash")
            }

            VStack(spacing: Space.m) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    IntroRow(symbol: row.symbol, title: row.title, detail: row.detail,
                             showsDivider: index < rows.count - 1)
                        .opacity(index < shown ? 1 : 0)
                        .offset(y: index < shown || reduceMotion ? 0 : 8)
                }
            }
            .padding(.top, Space.xxl)

            Spacer(minLength: 0)
        }
        .task {
            for index in rows.indices {
                try? await Task.sleep(for: .seconds(index == 0 ? 0.25 : 0.35))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.respecting(reduceMotion, Motion.reveal)) { shown = index + 1 }
            }
        }
    }
}

// MARK: - 3 · Example

private struct ExampleSlide: View {
    let profile: Profile
    let facts: IntroFacts

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(
                heading: "Take \(profile.name).",
                subtitle: Text("\(profile.age), putting \(OverviewCopy.percent(profile.currentEmployeeRate)) of pay\ninto a target-date fund.")
            ) {
                SetupAvatar(profile: profile)
                    .scaleEffect(SetupHeader<EmptyView>.iconSize / SetupAvatar.baseSize)
            }

            VStack(spacing: Space.xs) {
                if let debt = profile.debts.first {
                    row(debt.name, "\(Money.whole(profile.totalDebtCents)) · \(Int((debt.apr * 100).rounded()))% APR")
                }
                row("Emergency cash", cashCoverage)
                row("Retirement today", Money.whole(profile.retirementBalanceCents))
            }
            .padding(.top, Space.xl)

            if let final = facts.currentFinal {
                Text("On autopilot, at \(profile.retirementAge)")
                    .font(.geist(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(SetupStyle.secondaryText)
                    .padding(.top, Space.xl)

                SetupPill {
                    CountingMoney(cents: final)
                        .font(.numeral(34, .regular, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(.top, Space.s)

                if let debtContext {
                    Text(debtContext)
                        .font(SetupStyle.rowDetail)
                        .foregroundStyle(SetupStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.top, Space.m)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var cashCoverage: String {
        let months = OverviewCopy.monthsCount(profile.emergencyMonths)
        return "\(months) month\(months == "1" ? "" : "s") of expenses"
    }

    private var debtContext: String? {
        guard let month = facts.currentDebtFreeMonth, month > 0,
              let interest = facts.currentInterest, interest > 0,
              let debt = profile.debts.first else { return nil }
        return "On minimums, the \(debt.name.lowercased()) takes \(IntroFacts.duration(months: month))\nand \(Money.whole(interest)) in interest to clear."
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.geist(16, .regular, relativeTo: .body))
                .foregroundStyle(SetupStyle.secondaryText)
            Spacer(minLength: Space.m)
            Text(value)
                .font(.numeral(17, .medium, relativeTo: .body))
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 4 · Adaptive

private struct AdaptiveSlide: View {
    let profile: Profile
    let facts: IntroFacts

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var onCourse: Bool { facts.currentFinal != nil && facts.gain == nil && facts.interestSaved == nil }

    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(
                heading: onCourse ? "Already on course." : "Adaptive sees all of it.",
                subtitle: Text(onCourse
                    ? "Nothing urgent, so the fund stays on its path.\nAdaptive keeps checking as life changes."
                    : "Each month it splits your cash between the\nmatch, your debt, and your savings.")
            ) {
                HeaderGlyph(symbol: "arrow.triangle.branch")
            }

            GeometryReader { geo in
                ProjectionChart(adaptive: facts.adaptiveCurve,
                                comparison: facts.currentCurve,
                                adaptiveName: "Adaptive",
                                comparisonName: "Autopilot")
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: revealed ? geo.size.width : 0)
                    }
            }
            .frame(height: 140)
            .padding(.top, Space.xl)

            legend
                .padding(.top, Space.s)

            if let gain = facts.gain {
                SetupPill {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        CountingMoney(cents: gain, prefix: "+")
                            .font(.numeral(34, .regular, relativeTo: .largeTitle))
                            .foregroundStyle(Palette.accent)
                        Text("at \(profile.retirementAge)")
                            .font(SetupStyle.rowDetail)
                            .foregroundStyle(SetupStyle.secondaryText)
                    }
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                }
                .padding(.top, Space.xl)
            }

            if let context {
                Text(context)
                    .font(SetupStyle.rowDetail)
                    .foregroundStyle(SetupStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, Space.m)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .timingCurve(0.65, 0, 0.35, 1, duration: 1.4).delay(0.2)) {
                revealed = true
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Space.l) {
            HStack(spacing: 6) {
                Capsule().stroke(Palette.blue, style: StrokeStyle(lineWidth: 1.3, dash: [3, 2])).frame(width: 14, height: 1)
                Text("Autopilot")
            }
            HStack(spacing: 6) {
                Capsule().fill(Palette.accent).frame(width: 14, height: 1.5)
                Text("Adaptive")
            }
            Spacer(minLength: 0)
            Text(facts.isIllustrative ? Disclosure.illustrative : "Today → age \(profile.retirementAge)")
        }
        .font(.geist(12, .regular, relativeTo: .caption))
        .foregroundStyle(Palette.textCaption)
        .accessibilityHidden(true)
    }

    private var context: String? {
        var parts: [String] = []
        if let now = facts.adaptiveDebtFreeMonth, let before = facts.currentDebtFreeMonth, now < before {
            parts.append("Card paid off in \(IntroFacts.duration(months: now)), not \(IntroFacts.duration(months: before)).")
        }
        if let saved = facts.interestSaved {
            parts.append("\(Money.whole(saved)) less interest. Same fund, full match.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

// MARK: - 5 · How it works

private struct HowItWorksSlide: View {
    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(
                heading: "Here's how it works.",
                subtitle: Text("A quick setup, then one clear next step.")
            ) {
                HeaderGlyph(symbol: "sparkles")
            }

            VStack(spacing: Space.m) {
                IntroRow(symbol: "link", title: "See it all together",
                         detail: "Retirement, cash, and debt in one place", showsDivider: true)
                IntroRow(symbol: "list.number", title: "Get your priorities in order",
                         detail: "AI ranks them; our engine checks the rules", showsDivider: true)
                IntroRow(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Watch it play out",
                         detail: "Where each dollar goes, year by year", showsDivider: false)
            }
            .padding(.top, Space.xxl)

            Spacer(minLength: Space.l)

            Text("Every dollar is calculated, never generated. No trading.\nFictional profiles · Not affiliated with T. Rowe Price.")
                .font(.geist(11, .regular, relativeTo: .caption2))
                .foregroundStyle(SetupStyle.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.bottom, Space.l)
        }
    }
}

// MARK: - Shared pieces

/// Icon disc, title and detail, laid out like the focus rows.
private struct IntroRow: View {
    let symbol: String
    let title: String
    let detail: String
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: 0) {
            TopicDisc(symbol: symbol)
                .scaleEffect(48 / TopicDisc.baseSize)
                .frame(width: 48, height: 48)
                .padding(.leading, Space.m)
                .frame(width: 80, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(SetupStyle.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(SetupStyle.rowDetail)
                    .foregroundStyle(SetupStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 76)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(SetupStyle.divider)
                    .frame(height: 1)
                    .padding(.leading, 80)
                    .offset(y: Space.m / 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A whole-dollar amount that counts up from zero when it appears.
private struct CountingMoney: View {
    let cents: Int64
    var prefix = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var value: Double = 0

    var body: some View {
        CountingText(value: value, prefix: prefix)
            .onAppear {
                guard !reduceMotion else { value = Double(cents); return }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.2).delay(0.25)) { value = Double(cents) }
            }
            .onChange(of: cents) { _, new in
                withAnimation(Motion.respecting(reduceMotion, Motion.reveal)) { value = Double(new) }
            }
            .accessibilityLabel(prefix + Money.whole(cents))
    }
}

private struct CountingText: View, Animatable {
    var value: Double
    let prefix: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(prefix + Money.whole(Int64((value / 100).rounded()) * 100))
            .monospacedDigit()
    }
}

#Preview {
    ZStack {
        EmberAtmosphereView()
        IntroFlow()
    }
    .environmentObject(AppStore())
    .preferredColorScheme(.dark)
    .onAppear(perform: FontRegistry.registerAll)
}
