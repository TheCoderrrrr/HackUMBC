import SwiftUI

/// Modeling assumptions and limitations behind every projection.
struct AssumptionsSheet: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        // The response's own assumptions when a calculation is loaded; the Swift copy is
        // the offline fallback (REPORT B6).
        let model = AssumptionValues(store.evaluationLoad.current?.evaluation.assumptions)
        SheetScaffold(title: "Assumptions", subtitle: "Illustrative and nominal. Not forecasts.") {
            VStack(alignment: .leading, spacing: 0) {
                ServerSection()
                AssumptionSection(title: "Annual returns", note: model.returnsNetOfFees ? "Net of fees" : nil, rows: [
                    ("Stocks", pct(model.annualEquityReturn)),
                    ("Bonds", pct(model.annualBondReturn)),
                    ("Cash", pct(model.annualCashReturn))
                ])

                AssumptionSection(title: "Yearly growth", rows: [
                    ("Inflation", pct(model.annualInflation)),
                    ("Salary", pct(model.annualSalaryGrowth)),
                    ("Living costs", pct(model.annualLivingCostGrowth)),
                    ("Contribution limit", pct(model.annualEmployeeLimitGrowth))
                ])

                AssumptionSection(title: "Planning rules", rows: [
                    // The engine's threshold is inclusive: APR >= 10% (state.py).
                    ("High-interest debt", "At least \(pct(model.highInterestAPRThreshold)) APR"),
                    ("Total saving target", pct(model.retirementTotalSavingTarget)),
                    ("Starter reserve", SheetCopy.months(model.starterReserveMonths)),
                    ("Full reserve", SheetCopy.months(model.fullReserveMonths)),
                    ("Critical reserve cap", Money.whole(model.criticalReserveCapCents))
                ])

                AssumptionSection(title: "Stock allocation", note: Disclosure.allocationLabel, rows: model.glidePath.map { anchor in
                    (anchor.years == 0 ? "At retirement"
                        : anchor.years >= 30 ? "30+ years out" : "\(Int(anchor.years)) years out",
                     pct(anchor.equity))
                })

                SheetSectionTitle("Limitations")
                    .padding(.top, 19)
                    .padding(.bottom, Space.s)
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(model.limitations, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(Palette.textCaption)
                                .frame(width: 4, height: 4)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                            EmphasizedText(item, size: 15, style: .subheadline, lineSpacing: 4)
                        }
                    }
                }

                SourceCaption(lines: [Disclosure.fictional])
                    .padding(.top, Space.xl)
            }
        }
    }

    private func pct(_ value: Double) -> String { SheetCopy.percent(value) }
}

/// Display-ready assumptions: the evaluation response's `assumptions` when a calculation
/// is loaded, otherwise the bundled illustrative copy (REPORT B6).
private struct AssumptionValues {
    let returnsNetOfFees: Bool
    let annualEquityReturn: Double
    let annualBondReturn: Double
    let annualCashReturn: Double
    let annualInflation: Double
    let annualSalaryGrowth: Double
    let annualLivingCostGrowth: Double
    let annualEmployeeLimitGrowth: Double
    let highInterestAPRThreshold: Double
    let retirementTotalSavingTarget: Double
    let criticalReserveCapCents: Int64
    let starterReserveMonths: Double
    let fullReserveMonths: Double
    let glidePath: [(years: Double, equity: Double)]
    let limitations: [String]

    init(_ api: API.ModelAssumptions?) {
        if let api {
            returnsNetOfFees = api.returnsNetOfFees
            annualEquityReturn = api.annualEquityReturn
            annualBondReturn = api.annualBondReturn
            annualCashReturn = api.annualCashReturn
            annualInflation = api.annualInflation
            annualSalaryGrowth = api.annualSalaryGrowth
            annualLivingCostGrowth = api.annualLivingCostGrowth
            annualEmployeeLimitGrowth = api.annualEmployeeLimitGrowth
            highInterestAPRThreshold = api.highInterestAprThreshold
            retirementTotalSavingTarget = api.retirementTotalSavingTarget
            criticalReserveCapCents = api.criticalReserveCapCents
            starterReserveMonths = api.starterReserveMonths
            fullReserveMonths = api.fullReserveMonths
            glidePath = api.glidePath.map { (years: $0.yearsToRetirement, equity: $0.equityWeight) }
            limitations = api.limitations
        } else {
            let local = ModelAssumptions.illustrative
            returnsNetOfFees = local.returnsNetOfFees
            annualEquityReturn = local.annualEquityReturn
            annualBondReturn = local.annualBondReturn
            annualCashReturn = local.annualCashReturn
            annualInflation = local.annualInflation
            annualSalaryGrowth = local.annualSalaryGrowth
            annualLivingCostGrowth = local.annualLivingCostGrowth
            annualEmployeeLimitGrowth = local.annualEmployeeLimitGrowth
            highInterestAPRThreshold = local.highInterestAPRThreshold
            retirementTotalSavingTarget = local.retirementTotalSavingTarget
            criticalReserveCapCents = local.criticalReserveCapCents
            starterReserveMonths = Double(local.starterReserveMonths)
            fullReserveMonths = Double(local.fullReserveMonths)
            glidePath = local.glidePath.map { (years: Double($0.yearsToRetirement), equity: $0.equityWeight) }
            limitations = local.limitations
        }
    }
}

private struct AssumptionSection: View {
    let title: String
    var note: String? = nil
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetSectionTitle(title)
                .padding(.top, 19)
            if let note {
                Text(note)
                    .font(.geist(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Palette.textCaption)
                    .padding(.top, 4)
            }
            VStack(spacing: 0) {
                ForEach(rows, id: \.0) { row in
                    InputRow(label: row.0, value: row.1)
                }
            }
            .padding(.top, 8)
            Hairline(color: Palette.hairlineStrong)
                .padding(.top, 16)
        }
    }
}

/// Server URL for live calculations (the ngrok tunnel). HTTPS only; empty uses saved data.
private struct ServerSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var text = ""
    @State private var rejected = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetSectionTitle("Live calculation")
                .padding(.top, 19)
            Text("Paste the server's https:// address. Leave empty to use saved demo data.")
                .font(.geist(13, .regular, relativeTo: .footnote))
                .foregroundStyle(Palette.textCaption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: Space.s) {
                TextField("https://your-name.ngrok-free.app", text: $text)
                    .font(.geist(15, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textPrimary)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(save)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Server address")
                // With the saved URL in the field this becomes Reconnect, so there's always
                // a way to force a fresh request from this sheet (REPORT E4).
                Button(text == store.serverBaseURL ? "Reconnect" : "Save",
                       action: text == store.serverBaseURL ? reconnect : save)
                    .font(.geist(15, .medium, relativeTo: .callout))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(PressableStyle())
                    .frame(minHeight: 44)
            }
            .padding(.top, 8)
            HStack(spacing: Space.s) {
                if rejected {
                    Text("Use a full https:// address.")
                        .font(.geist(13, .regular, relativeTo: .footnote))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    LiveStatusRow()
                }
            }
            .frame(minHeight: 44)
            Hairline(color: Palette.hairlineStrong)
                .padding(.top, 8)
        }
        .onAppear { text = store.serverBaseURL }
        .onChange(of: text) { _, _ in rejected = false }
    }

    private func save() {
        focused = false
        rejected = !store.setServerBaseURL(text)
        if !rejected { text = store.serverBaseURL }
    }

    private func reconnect() {
        focused = false
        store.refreshEvaluation()
    }
}
