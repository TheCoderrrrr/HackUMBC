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
                Task { await model.save(evaluation: toSave.evaluation, scenario: toSave.scenario,
                                        planningPreference: store.planStyle, client: store.apiClient) }
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
                    Text("\(run.label) · \(run.fundName ?? "generic fund model") · saved \(FundCopy.savedAt(run.createdAt))")
                        .tag(Optional(run.runID))
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

            YearlyComparisonChart(series: [
                YearlySeries(name: comparison.base.label, values: base, style: .baseline),
                YearlySeries(name: comparison.other.label, values: other, style: .primary),
            ])
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
