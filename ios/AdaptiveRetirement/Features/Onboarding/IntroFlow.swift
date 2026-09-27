import SwiftUI

/// Splash → intro → setup. Five slides that make the case before the walkthrough:
/// what a target-date fund knows, what it misses, what that costs this profile,
/// and what Adaptive does about it. Every dollar figure comes from the engine's
/// current (autopilot) and adaptive projections; without an evaluation the slides
/// fall back to profile facts and schematic curves.
enum IntroSlide: Int, CaseIterable, Comparable {
    case autopilot, blindSpots, example, adaptive, howItWorks
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }

    var next: IntroSlide? { IntroSlide(rawValue: rawValue + 1) }
    var previous: IntroSlide? { IntroSlide(rawValue: rawValue - 1) }

    /// Seconds before auto-advancing, sized to the reading load. The last slide waits.
    var dwell: Double? {
        switch self {
        case .autopilot: 6
        case .blindSpots: 7
        case .example: 9
        case .adaptive: 9
        case .howItWorks: nil
        }
    }
}

struct IntroFlow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// Fill of the current progress segment, 0…1.
    @State private var progress: Double = 0
    /// Pressing on the slide holds the slideshow.
    @GestureState private var holding = false

    private var slide: IntroSlide { store.introSlide }
    private var profile: Profile { store.displayProfile }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                ZStack(alignment: .top) {
                    slideContent
                        .id(slide)
                        .transition(transition)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .contentShape(Rectangle())
                .gesture(navigationGesture(width: geo.size.width))
            }
            .padding(.top, Space.xl)

            actions
        }
        .padding(.horizontal, SetupStyle.gutter)
        .sensoryFeedback(trigger: slide) { old, new in
            .impact(weight: new > old ? .medium : .light)
        }
        .task(id: slide) { await runSlide() }
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

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: Space.l) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(SetupStyle.disc, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Back")
            .opacity(slide.previous == nil ? 0 : 1)
            .disabled(slide.previous == nil)

            HStack(spacing: 6) {
                ForEach(IntroSlide.allCases, id: \.self) { item in
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Palette.textPrimary)
                                    .frame(width: geo.size.width * fill(for: item))
                            }
                        }
                        .frame(height: 3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Intro")
            .accessibilityValue("\(slide.rawValue + 1) of \(IntroSlide.allCases.count)")

            // Balances the back button so the segments stay centred.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, Space.s)
    }

    private func fill(for item: IntroSlide) -> Double {
        if item < slide { return 1 }
        if item > slide { return 0 }
        return slide.dwell == nil ? 1 : progress
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Space.s) {
            Button(action: advance) {
                Text(slide.next == nil ? "Try it with \(store.profile.name)" : "Next")
                    .contentTransition(.opacity)
            }
            .buttonStyle(SetupPrimaryButtonStyle())

            // Space stays reserved so the primary button doesn't jump on the last slide.
            Button(action: finish) {
                Text("Skip intro")
                    .font(SetupStyle.secondaryAction)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .opacity(slide.next == nil ? 0 : 1)
            .disabled(slide.next == nil)
        }
        .padding(.bottom, 15)
    }

    // MARK: Navigation

    /// Tap the right two-thirds to go forward, the left third to go back; swipe either way.
    /// Pressing holds the auto-advance.
    private func navigationGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($holding) { _, state, _ in state = true }
            .onEnded { value in
                let dx = value.translation.width
                if abs(dx) > 40, abs(dx) > abs(value.translation.height) {
                    dx < 0 ? advanceIfPossible() : back()
                } else if abs(dx) < 10, abs(value.translation.height) < 10 {
                    value.location.x < width / 3 ? back() : advanceIfPossible()
                }
            }
    }

    /// Fills the current segment, then moves on. Paused while pressing; off under VoiceOver.
    private func runSlide() async {
        progress = 0
        guard let dwell = slide.dwell, !voiceOver, !Self.holdsSlides else { return }
        let tick = 1.0 / 30
        while progress < 1 {
            try? await Task.sleep(for: .seconds(tick))
            guard !Task.isCancelled else { return }
            if !holding { progress = min(1, progress + tick / dwell) }
        }
        advanceIfPossible()
    }

    private func advance() {
        if slide.next == nil { finish() } else { advanceIfPossible() }
    }

    private func advanceIfPossible() {
        guard let next = slide.next else { return }
        go(to: next)
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

    /// `-hold 1` stops auto-advance for screenshots.
    private static var holdsSlides: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "hold")
        #else
        false
        #endif
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

private struct AutopilotSlide: View {
    var body: some View {
        VStack(spacing: 0) {
            SetupHeader(
                heading: "Your 401(k) runs on one number.",
                subtitle: Text("Target-date funds are the default in many\nplans. They only know when you'll retire.")
            ) {
                HeaderGlyph(symbol: "calendar")
            }

            GlidePathVisual()
                .frame(height: 190)
                .padding(.top, Space.xxl)

            Text("As retirement nears, it shifts from stocks to bonds.\nNothing else about you changes the plan.")
                .font(SetupStyle.rowDetail)
                .foregroundStyle(SetupStyle.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, Space.xl)

            Spacer(minLength: 0)
        }
    }
}

/// Stocks vs bonds from age 25 to 65 along the illustrative glide path, swept in left to right.
private struct GlidePathVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private static let startAge = 25
    private static let endAge = 65
    private let glide = ModelAssumptions.illustrative.glidePath

    var body: some View {
        VStack(spacing: Space.s) {
            GeometryReader { geo in
                let equity = samples()
                ZStack {
                    area(equity, in: geo.size, top: true)
                        .fill(LinearGradient(colors: [Palette.blue.opacity(0.30), Palette.blue.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom))
                    area(equity, in: geo.size, top: false)
                        .fill(LinearGradient(colors: [Color(hex: 0x86DB8F).opacity(0.42), Color(hex: 0x86DB8F).opacity(0.10)],
                                             startPoint: .top, endPoint: .bottom))
                        .fillGrain()
                    line(equity, in: geo.size)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))

                    VStack {
                        label("Bonds", color: Palette.blue)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, Space.s)
                        Spacer()
                        label("Stocks", color: Palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, Space.m)
                    }
                    .padding(.horizontal, Space.m)
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: revealed ? geo.size.width : 0)
                }
            }

            HStack {
                Text("Age \(Self.startAge) · 90% stocks")
                Spacer(minLength: 0)
                Text("Age \(Self.endAge) · 50%")
            }
            .font(.geist(12, .regular, relativeTo: .caption))
            .foregroundStyle(Palette.textCaption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustrative glide path: 90% stocks at age 25, easing to 50% at 65.")
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
                .font(.geist(12, .medium, relativeTo: .caption))
                .foregroundStyle(Palette.textPrimary.opacity(0.85))
        }
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

    private func point(_ i: Int, _ values: [Double], _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                y: size.height * CGFloat(1 - values[i]))
    }

    private func line(_ values: [Double], in size: CGSize) -> Path {
        Path { p in
            for i in values.indices {
                if i == 0 { p.move(to: point(i, values, size)) } else { p.addLine(to: point(i, values, size)) }
            }
        }
    }

    /// The band above (bonds) or below (stocks) the equity line.
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
