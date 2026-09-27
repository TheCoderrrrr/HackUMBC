import SwiftUI
import Charts

/// Explore › Scenario history: save the result on screen, then compare two saved runs of
/// this profile over 5, 10 and 20 years. Runs are stored as time series in Tiger Data; every
/// value shown comes from the server's comparison query.
struct ScenarioHistorySection: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var model: HistoryModel
    let profile: Profile
    /// The compared scenario's result, if one is shown; otherwise the plan as is is saved.
    let scenarioResult: API.Evaluation?
    let scenario: API.Scenario?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scenario history")
                .font(.geist(21, .medium, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Text("Saved runs, stored as time series in Tiger Data")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textSecondary)

            switch model.phase {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.textCaption)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Checking scenario history")
            case .unavailable(let message):
                caption(message)
            case .ready:
                saveRow
                if let blocker = saveBlocker { caption(blocker) }
                if let note = model.note { caption(note) }
                picker
                comparison
            }
        }
        .task(id: "\(profile.id)|\(store.serverGeneration)") {
            await model.refresh(profileID: profile.id, client: store.apiClient)
        }
        .task(id: model.pairKey) {
            await model.compare(client: store.apiClient)
        }
        .animation(Motion.reveal, value: model.phase)
    }

    // MARK: Save

    /// What "Save to history" would save: the compared scenario, else the plan on screen.
    private var toSave: (evaluation: API.Evaluation, scenario: API.Scenario?)? {
        if let scenarioResult { return (scenarioResult, scenario) }
        return profile.evaluation.map { ($0, nil) }
    }

    private var saveBlocker: String? {
        guard let toSave else { return "Calculate the plan first, then save it." }
        if toSave.scenario != nil, toSave.evaluation.projections.custom?.feasible == false {
            return "Only scenarios that can be funded can be saved."
        }
        return nil
    }

    private var saveRow: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Text(scenarioResult == nil ? "Save the plan as is to compare it later."
                                       : "Save this scenario to compare it later.")
                .font(.geist(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            Button {
                guard let toSave else { return }
                Task { await model.save(evaluation: toSave.evaluation, scenario: toSave.scenario, client: store.apiClient) }
            } label: {
                HStack(spacing: 6) {
                    if model.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    Text("Save to history")
                }
                .font(.geist(15, .medium, relativeTo: .callout))
                .padding(.horizontal, Space.l)
            }
            .buttonStyle(SecondaryButtonStyle(bordered: true))
            .fixedSize()
            .disabled(model.isSaving || saveBlocker != nil)
            .opacity(saveBlocker != nil ? 0.45 : 1)
        }
        .padding(.top, Space.l)
    }

    // MARK: Pick two runs

    @ViewBuilder
    private var picker: some View {
        switch model.runs.count {
        case 0:
            caption("No saved runs yet.")
        case 1:
            caption("Save one more run to compare the two over time.")
        default:
            VStack(spacing: 0) {
                runPicker("Compare", selection: $model.basePick, excluding: model.otherPick, dashed: true)
                runPicker("with", selection: $model.otherPick, excluding: model.basePick, dashed: false)
            }
            .padding(.top, Space.l)
        }
    }

    private func runPicker(_ title: String, selection: Binding<String?>, excluding: String?, dashed: Bool) -> some View {
        HStack(spacing: Space.m) {
            SeriesSwatch(color: dashed ? Palette.blue : Palette.accent, dashed: dashed)
            Text(title)
                .font(.geist(15, .regular, relativeTo: .callout))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 70, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(model.runs.filter { $0.runID != excluding }) { run in
                    Text("\(run.label) · saved \(FundCopy.savedAt(run.createdAt))").tag(Optional(run.runID))
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.textPrimary)
            .labelsHidden()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
    }

    // MARK: Comparison

    @ViewBuilder
    private var comparison: some View {
        switch model.comparison {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView().controlSize(.small).frame(minHeight: 44)
        case .failed(let message):
            caption(message)
        case .loaded(let comparison):
            ComparisonDetail(comparison: comparison, profile: profile)
                .padding(.top, Space.l)
                .transition(.opacity)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.geist(13, .regular, relativeTo: .footnote))
            .foregroundStyle(Palette.textCaption)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.s)
    }
}

/// The chart, the 5/10/20-year rows and the source line for one comparison.
private struct ComparisonDetail: View {
    let comparison: API.History.Comparison
    let profile: Profile

    var body: some View {
        let base = Self.series(comparison.years) { $0.base }
        let other = Self.series(comparison.years) { $0.other }
        let span = max(base.count, other.count) - 1
        let startYear = Int(comparison.asOfDate.prefix(4)) ?? ExploreTimeline.startYear

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                legend(comparison.base.label, color: Palette.blue, dashed: true)
                legend(comparison.other.label, color: Palette.accent, dashed: false)
            }
            .frame(minHeight: 28)

            HistoryChart(base: base, other: other)
                .frame(height: 190)
                .padding(.top, Space.s)
                .accessibilityLabel("Retirement balance over time: \(comparison.base.label), dashed, compared with \(comparison.other.label), solid")

            if span > 0 {
                HStack {
                    axisLabel("\(startYear)")
                    Spacer()
                    axisLabel("\(startYear + span / 2)")
                    Spacer()
                    axisLabel("\(startYear + span) · Age \(profile.age + span)")
                }
                .frame(minHeight: 26)
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Space.l) {
                ForEach(comparison.horizons, id: \.years) { horizon in
                    HorizonRow(horizon: horizon)
                }
            }
            .padding(.top, Space.l)

            Text("From Tiger Data: yearly points of each run's time series. \(decision(comparison.base)) → \(decision(comparison.other)) · model \(comparison.other.modelVersion) · policy \(comparison.other.policyVersion). Projected dates under illustrative assumptions, not observed data.")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.l)
        }
    }

    /// Yearly retirement balance for one run, cut at its first missing year (it retired sooner).
    static func series(_ years: [API.History.ComparisonPoint], _ side: (API.History.ComparisonPoint) -> API.History.YearValues?) -> [Double] {
        var values: [Double] = []
        for year in years {
            guard let value = side(year) else { break }
            values.append(Double(value.retirementBalanceCents))
        }
        return values
    }

    private func decision(_ run: API.History.RunSummary) -> String { run.isAIDecision ? "AI decision" : "Rules decision" }

    private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 7) {
            SeriesSwatch(color: color, dashed: dashed)
            Text(title)
                .font(.geist(13, dashed ? .regular : .medium, relativeTo: .footnote))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.geist(12, .medium, relativeTo: .caption))
            .foregroundStyle(Palette.textCaption)
    }
}

/// "5 years · Sep 2031": retirement, emergency cash and debt for both runs, "base → other".
private struct HorizonRow: View {
    let horizon: API.History.Horizon

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(horizon.years) years · \(ExploreTimeline.label(forMonth: horizon.point.month))")
                .font(.geist(15, .medium, relativeTo: .callout))
                .foregroundStyle(Palette.textPrimary)
            line("Retirement") { $0.retirementBalanceCents }
            line("Emergency cash") { $0.cashCents }
            line("Debt") { $0.debtCents }
        }
        .accessibilityElement(children: .combine)
    }

    private func line(_ title: String, _ value: (API.History.YearValues) -> Int64) -> some View {
        HStack {
            Text(title)
                .font(.geist(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            (side(horizon.point.base.map(value), emphasized: false)
             + Text("  →  ").font(.geist(13, .regular, relativeTo: .footnote)).foregroundColor(Palette.textCaption)
             + side(horizon.point.other.map(value), emphasized: true))
                .monospacedDigit()
        }
    }

    /// A run with no point at this horizon has already retired.
    private func side(_ cents: Int64?, emphasized: Bool) -> Text {
        guard let cents else {
            return Text("Retired").font(.geist(13, .regular, relativeTo: .footnote)).foregroundColor(Palette.textQuiet)
        }
        return Text(Money.whole(cents))
            .font(.numeral(13, emphasized ? .medium : .regular, relativeTo: .footnote))
            .foregroundColor(emphasized ? Palette.textPrimary : Palette.textSecondary)
    }
}

/// Two runs on a shared year axis, in the style of Explore's Current vs Adaptive chart: faded
/// unstacked areas under a dashed blue and a solid accent line. Unlike that chart, series aren't
/// stretched to full width, so a run that retires sooner ends sooner.
private struct HistoryChart: View {
    let base: [Double]
    let other: [Double]

    private struct Point: Identifiable {
        let id: Int
        let year: Int
        let value: Double
        let series: String
    }

    private static let domain = ["Compare", "With"]

    var body: some View {
        let lastYear = Double(max(base.count, other.count, 2) - 1)
        let yMax = max(base.max() ?? 1, other.max() ?? 1, 1) * 1.04
        ZStack {
            Chart(points) { point in
                AreaMark(x: .value("Year", point.year), y: .value("Balance", point.value), stacking: .unstacked)
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Run", point.series))
            }
            .chartForegroundStyleScale(domain: Self.domain,
                                       range: [fade(Palette.blue, top: 0.26, mid: 0.09),
                                               fade(Color(hex: 0x86DB8F), top: 0.36, mid: 0.14)])
            .modifier(Axes(lastYear: lastYear, yMax: yMax))
            .fillGrain()

            Chart {
                ForEach([0.12, 0.42, 0.72], id: \.self) { y in
                    RuleMark(y: .value("Guide", y * yMax))
                        .foregroundStyle(Palette.hairline)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(points) { point in
                    LineMark(x: .value("Year", point.year), y: .value("Balance", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("Run", point.series))
                        .lineStyle(point.series == "Compare"
                                   ? StrokeStyle(lineWidth: 1.15, lineCap: .round, dash: [3, 4])
                                   : StrokeStyle(lineWidth: 1.65, lineCap: .round))
                }
                if let end = other.last {
                    PointMark(x: .value("Year", other.count - 1), y: .value("Balance", end))
                        .symbolSize(40)
                        .foregroundStyle(Palette.accent)
                }
            }
            .chartForegroundStyleScale(domain: Self.domain, range: [Palette.blue.opacity(0.9), Palette.accent])
            .modifier(Axes(lastYear: lastYear, yMax: yMax))
        }
        .accessibilityElement(children: .ignore)
    }

    private var points: [Point] {
        base.enumerated().map { Point(id: $0.offset, year: $0.offset, value: $0.element, series: "Compare") }
            + other.enumerated().map { Point(id: 10_000 + $0.offset, year: $0.offset, value: $0.element, series: "With") }
    }

    private func fade(_ color: Color, top: Double, mid: Double) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: color.opacity(top), location: 0),
            .init(color: color.opacity(mid), location: 0.5),
            .init(color: color.opacity(0), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    private struct Axes: ViewModifier {
        let lastYear: Double
        let yMax: Double
        func body(content: Content) -> some View {
            content
                .chartXScale(domain: 0...lastYear)
                .chartYScale(domain: 0...yMax)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
        }
    }
}

/// A short line sample: dashed for "Compare", solid for "with".
private struct SeriesSwatch: View {
    let color: Color
    let dashed: Bool

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 1))
            p.addLine(to: CGPoint(x: 17, y: 1))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
        .frame(width: 17, height: 2)
        .accessibilityHidden(true)
    }
}
