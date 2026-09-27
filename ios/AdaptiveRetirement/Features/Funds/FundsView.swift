import SwiftUI

/// Funds: an explainable shortlist of up to three target-date funds from a small catalog
/// verified against SEC filings. The user picks the account and risk tolerance; the server
/// filters, ranks and cites every figure. Nothing here ranks or calculates.
struct FundsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = FundsModel()
    @State private var selected: API.Funds.Recommendation?
    @State private var showsExcluded = false
    @State private var isScrolled = !ScreenHeaderScroll.isTrackable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Retirement funds that fit your choices.")
                    .font(.geist(16, .regular, relativeTo: .body))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.bottom, Space.xl)

                inputs
                Hairline(color: Palette.hairlineStrong)
                    .padding(.vertical, Space.xl)
                results
                footer
                    .padding(.top, Space.xl)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .tracksScrolled($isScrolled)
        .defaultScrollAnchor(Self.debugScrollAnchor)
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Funds", isScrolled: isScrolled) { HeaderAvatarButton() }
        }
        .sheet(item: $selected) { recommendation in
            FundDetailSheet(recommendation: recommendation,
                            detail: envelope?.details[recommendation.fundID],
                            shortlist: envelope?.shortlist)
                .presentationDetents([.large])
        }
        .onChange(of: store.profile.id, initial: true) { _, _ in
            model.reset(retirementYear: OverviewCopy.retirementYear(for: store.displayProfile))
            showsExcluded = false
        }
        .task(id: store.serverGeneration) {
            model.forgetCatalog()
            await model.loadCatalog(client: store.apiClient)
            #if DEBUG
            await debugAutoRun()
            #endif
        }
        .animation(Motion.reveal, value: model.account)
        .animation(Motion.reveal, value: model.menuKnown)
        .onAppear { updateChatContext() }
        .onReceive(model.objectWillChange) { _ in
            Task { @MainActor in updateChatContext() }
        }
    }

    private func updateChatContext() {
        var facts = [
            EducationScreenFact(label: "account_type", value: model.account.rawValue),
            EducationScreenFact(label: "selected_risk_tolerance", value: model.risk.rawValue),
            EducationScreenFact(label: "selected_retirement_year", value: String(model.retirementYear)),
            EducationScreenFact(label: "plan_menu_known", value: String(model.menuKnown)),
            EducationScreenFact(label: "ranking_method", value: "horizon fit, stock allocation risk fit, fund fees, verified data completeness"),
            EducationScreenFact(label: "risk_scale", value: "1 to 5, based on current stock weight, not volatility")
        ]
        if let catalog = model.catalog.value {
            facts.append(EducationScreenFact(label: "catalog_published_on", value: catalog.publishedOn))
        }
        if let shortlist = model.shortlist.value?.shortlist {
            facts.append(EducationScreenFact(label: "shortlist_count", value: String(shortlist.recommendations.count)))
            for (index, fund) in shortlist.recommendations.prefix(3).enumerated() {
                let key = "fund_\(index + 1)"
                facts += [
                    EducationScreenFact(label: "\(key)_name", value: String(fund.name.prefix(120))),
                    EducationScreenFact(label: "\(key)_target_year", value: String(fund.targetYear)),
                    EducationScreenFact(label: "\(key)_expense_ratio", value: String(format: "%.2f%%", fund.expenseRatio * 100)),
                    EducationScreenFact(label: "\(key)_stock_mix", value: String(format: "%.1f%%", fund.equityWeight * 100)),
                    EducationScreenFact(label: "\(key)_risk_band_out_of_five", value: String(fund.riskBand)),
                    EducationScreenFact(label: "\(key)_availability", value: fund.availabilityLabel.rawValue),
                    EducationScreenFact(label: "\(key)_facts_as_of", value: fund.factsAsOfDate)
                ]
                if let base = fund.hypotheticalScenarios.first(where: { $0.label == "base" }) {
                    facts.append(EducationScreenFact(label: "\(key)_hypothetical_base_annual_return", value: String(format: "%.1f%%", base.annualNetReturnRate * 100)))
                }
                if let history = fund.historicalReturns.first {
                    let rate = String(format: "%.1f%%", history.annualizedReturnRate * 100)
                    facts.append(EducationScreenFact(label: "\(key)_historical_return", value: "\(rate) annualized over \(history.periodYears) years as of \(history.asOfDate)"))
                }
            }
        }
        store.chatScreenFacts[.funds] = facts
    }

    private var envelope: API.Funds.Envelope? { model.shortlist.value }

    /// `-scroll center|bottom` (DEBUG) opens scrolled, for screenshots; as in Explore.
    private static var debugScrollAnchor: UnitPoint? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "scroll") {
        case "bottom": return .bottom
        case "center": return .center
        default: break
        }
        #endif
        return nil
    }

    #if DEBUG
    /// `-fundsAutoRun 1` requests the shortlist on appear, for screenshots; `-fundsAutoRun detail`
    /// also opens the first result. `-fundsAccount ira` and `-fundsRisk growth` set the inputs first.
    private func debugAutoRun() async {
        let defaults = UserDefaults.standard
        guard let mode = defaults.string(forKey: "fundsAutoRun") else { return }
        if let account = defaults.string(forKey: "fundsAccount").flatMap(API.Funds.AccountType.init) { model.account = account }
        if let risk = defaults.string(forKey: "fundsRisk").flatMap(API.Funds.RiskTolerance.init) { model.risk = risk }
        model.requestShortlist(client: store.apiClient)
        guard mode == "detail" else { return }
        for _ in 0..<50 where model.shortlist.isLoading { try? await Task.sleep(for: .milliseconds(100)) }
        selected = model.shortlist.value?.shortlist.recommendations.first
    }
    #endif

    // MARK: Inputs

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Find a target-date fund")
                .font(.geist(21, .medium, relativeTo: .title3))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(FundCopy.intro)
                .font(.geist(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)

            fieldLabel("Account")
            Picker("Account", selection: $model.account) {
                ForEach(API.Funds.AccountType.allCases, id: \.self) { Text(FundCopy.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)

            fieldLabel("Risk tolerance")
            Picker("Risk tolerance", selection: $model.risk) {
                ForEach(API.Funds.RiskTolerance.allCases, id: \.self) { Text(FundCopy.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            caption("You choose this. It is not inferred from age, income, or debt.")

            HStack {
                Text("Retirement year")
                    .font(.geist(17, .medium, relativeTo: .body))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                WordRoll(text: String(model.retirementYear))
                    .font(.numeral(18, .medium, relativeTo: .body))
                    .foregroundStyle(Palette.textPrimary)
                Stepper("Retirement year", value: $model.retirementYear, in: model.yearRange)
                    .labelsHidden()
                    .fixedSize()
                    .padding(.leading, Space.m)
            }
            .frame(minHeight: 44)
            .padding(.top, 18)

            if model.account == .k401 {
                planMenu
                    .transition(.opacity)
            }

            Button {
                model.requestShortlist(client: store.apiClient)
            } label: {
                HStack(spacing: Space.s) {
                    if model.shortlist.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "list.number")
                    }
                    Text("Show shortlist")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.shortlist.isLoading || menuIsEmpty)
            .padding(.top, 22)

            if let catalog = model.catalog.value {
                Footnote(text: "Catalog \(catalog.catalogVersion), reviewed by \(catalog.reviewedBy) on \(FundCopy.asOf(catalog.publishedOn)). \(catalog.reviewNote)")
                    .padding(.top, Space.m)
            }
        }
        .sensoryFeedback(.selection, trigger: model.risk)
        .sensoryFeedback(.selection, trigger: model.account)
    }

    /// A confirmed menu with nothing ticked can't match any fund.
    private var menuIsEmpty: Bool { model.account == .k401 && model.menuKnown && model.menu.isEmpty }

    private var planMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $model.menuKnown) {
                Text("I know my plan's fund menu")
                    .font(.geist(15, .regular, relativeTo: .callout))
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.accentStrong)
            .frame(minHeight: 44)
            .padding(.top, 14)
            caption(model.menuKnown
                    ? "Only funds you tick can be recommended."
                    : "Without your menu, results are research candidates your plan may not offer.")

            if model.menuKnown {
                switch model.catalog {
                case .loaded(let catalog):
                    VStack(spacing: 0) {
                        ForEach(catalog.funds) { fund in
                            MenuFundRow(fund: fund, isOn: model.menu.contains(fund.fundID)) {
                                if model.menu.contains(fund.fundID) { model.menu.remove(fund.fundID) } else { model.menu.insert(fund.fundID) }
                            }
                        }
                    }
                    .padding(.top, Space.s)
                case .loading:
                    ProgressView().controlSize(.small).padding(.top, Space.m)
                case .failed(let message):
                    caption("The fund list couldn't load: \(message)")
                case .idle:
                    caption("Connect to the live server to choose from the fund list.")
                }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        switch model.shortlist {
        case .idle, .loading:
            EmptyState(title: "A short, sourced list",
                       message: "Choose your account and risk tolerance, then show the shortlist. Every fee, mix and return comes with its filing and date.")
        case .failed(let message):
            EmptyState(title: "No shortlist yet", message: message)
        case .loaded(let envelope):
            loaded(envelope)
        }
    }

    @ViewBuilder
    private func loaded(_ envelope: API.Funds.Envelope) -> some View {
        let shortlist = envelope.shortlist
        VStack(alignment: .leading, spacing: 0) {
            if !envelope.unmatchedPlanMenuIDs.isEmpty {
                caption("Not in our reviewed catalog: \(envelope.unmatchedPlanMenuIDs.joined(separator: ", ")).")
                    .padding(.bottom, Space.m)
            }

            if shortlist.recommendations.isEmpty {
                if shortlist.isEntirelyStale {
                    EmptyState(title: "Fund data needs a refresh",
                               message: "The verified fund data is past its 90-day freshness window, so nothing can be ranked until the catalog is refreshed. We don't fill gaps with estimates.")
                } else {
                    EmptyState(title: "No fund qualifies",
                               message: "None of the reviewed funds passed the checks below. We don't fill gaps with estimates.")
                }
            } else {
                Text("Your shortlist")
                    .font(.geist(21, .medium, relativeTo: .title3))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: Space.l) {
                    ForEach(Array(shortlist.recommendations.enumerated()), id: \.element.id) { index, recommendation in
                        FundCard(rank: index + 1, recommendation: recommendation,
                                 detail: envelope.details[recommendation.fundID]) {
                            selected = recommendation
                        }
                    }
                }
                .padding(.top, Space.s)
            }

            if !shortlist.excluded.isEmpty {
                excluded(shortlist.excluded)
                    .padding(.top, Space.xl)
            }

            SourceCaption(lines: [shortlist.hypotheticalDisclosure,
                                  "Assumptions \(shortlist.assumptionSetVersion), as of **\(FundCopy.asOf(shortlist.assumptionSetAsOfDate))**."])
                .padding(.top, Space.l)
        }
    }

    private func excluded(_ funds: [API.Funds.Excluded]) -> some View {
        let names = Dictionary(model.catalog.value?.funds.map { ($0.fundID, $0.name) } ?? [], uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.reveal) { showsExcluded.toggle() }
            } label: {
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not recommended")
                            .font(.geist(17, .medium, relativeTo: .headline))
                            .foregroundStyle(Palette.textPrimary)
                        Text("Reviewed funds that did not pass a check")
                            .font(.geist(12, .regular, relativeTo: .caption))
                            .foregroundStyle(Palette.textCaption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textCaption)
                        .rotationEffect(.degrees(showsExcluded ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 1, dim: 0.7))
            .accessibilityLabel("Not recommended, \(funds.count) funds")

            if showsExcluded {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(funds, id: \.fundID) { fund in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(names[fund.fundID] ?? fund.fundID)
                                .font(.geist(14, .regular, relativeTo: .subheadline))
                                .foregroundStyle(Palette.textSecondary)
                            Text(FundCopy.exclusion(fund.reasonCode))
                                .font(.geist(12, .regular, relativeTo: .caption))
                                .foregroundStyle(Palette.textCaption)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, Space.s)
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: showsExcluded)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            LiveStatusRow()
            Text("Fund data from SEC filings and issuer reports · hypothetical illustrations are not forecasts · not investment advice.")
                .font(.geist(12, .regular, relativeTo: .caption))
                .foregroundStyle(Palette.textCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pieces

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.geist(17, .medium, relativeTo: .body))
            .foregroundStyle(Palette.textPrimary)
            .padding(.top, 18)
            .padding(.bottom, Space.m)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.geist(13, .regular, relativeTo: .footnote))
            .foregroundStyle(Palette.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 11)
    }
}

/// Title plus one quiet sentence, for idle, empty and failed results.
private struct EmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(.geist(17, .medium, relativeTo: .headline))
                .foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(.geist(14, .regular, relativeTo: .subheadline))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One catalog fund with a checkmark, for the 401(k) plan menu.
private struct MenuFundRow: View {
    let fund: API.Funds.CatalogEntry
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Space.m) {
                ZStack {
                    Circle().fill(isOn ? Palette.accentStrong : Palette.raised)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
                Text(fund.name + (fund.ticker.map { " (\($0))" } ?? ""))
                    .font(.geist(14, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99, dim: 0.8))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(Motion.select, value: isOn)
    }
}
