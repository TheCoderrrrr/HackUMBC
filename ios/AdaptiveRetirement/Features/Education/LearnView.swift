import SwiftUI

/// The six web lessons, with facts from the selected evaluation and actions in native screens.
struct LearnView: View {
    @EnvironmentObject private var store: AppStore

    private var profile: Profile { store.displayProfile }
    private var assumptions: API.ModelAssumptions? { profile.evaluation?.assumptions }
    private var fullMatchRate: Double? { profile.evaluation?.financialState.employeeRateForFullMatch }
    private var costlyDebt: Debt? {
        let threshold = assumptions?.highInterestAprThreshold ?? ModelAssumptions.illustrative.highInterestAPRThreshold
        return profile.debts.filter { $0.apr >= threshold }.max { $0.apr < $1.apr }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Six ideas behind your plan. Try one with your own numbers.")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textSecondary)
                Button("Choose a plan style") { store.openStyleGuide() }
                    .font(TypeScale.labelMedium)
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                Button("Getting started") { store.sheet = .gettingStarted }
                    .font(TypeScale.labelMedium)
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)

                lesson("Get the full employer match", icon: "checkmark.seal",
                       body: "Your employer match is money added when you contribute. Missing it is like turning down part of your pay.",
                       yours: fullMatchRate.map { "You contribute \(pct(profile.currentEmployeeRate)); the full match needs \(pct($0))." }
                           ?? "No confirmed employer match on your profile.",
                       action: fullMatchRate.map { "Try \(pct($0))" }, run: {
                    if let rate = fullMatchRate { store.tryLearnScenario(retirementAge: profile.retirementAge, rate: rate) }
                })
                lesson("Give money time to grow", icon: "clock.arrow.circlepath",
                       body: "With compound growth, each extra year invested can add to the gains from earlier years.",
                       yours: "You plan to retire at \(profile.retirementAge), in \(profile.yearsToRetirement) years.",
                       action: profile.retirementAge < 80 ? "Try retiring at \(min(profile.retirementAge + 2, 80))" : nil,
                       run: { store.tryLearnScenario(retirementAge: min(profile.retirementAge + 2, 80), rate: nil) })
                lesson("Clear expensive debt early", icon: "flag",
                       body: "Paying down high-interest debt avoids its APR in interest, often more than investing can reliably earn.",
                       yours: costlyDebt.map { "\($0.name): \(Money.whole($0.balanceCents)) at \(pct($0.apr)) APR." }
                           ?? "You have no high-interest debt.",
                       action: "Try Debt payoff first", run: { openStyle(.debtReduction) })
                lesson("Keep an emergency fund", icon: "umbrella",
                       body: "An emergency fund keeps a surprise bill from turning into new debt. ARM builds a small cushion first.",
                       yours: "You have \(String(format: "%.1f", profile.emergencyMonths)) months saved; the full target is \(profile.fullTargetMonths) months.",
                       action: "Try Cash security first", run: { openStyle(.cashSecurity) })
                lesson("Read future balances in today's dollars", icon: "slider.horizontal.3",
                       body: "Prices rise over time, so inflation matters when you read a future balance.",
                       yours: "The model assumes \(pct(assumptions?.annualInflation ?? ModelAssumptions.illustrative.annualInflation)) inflation a year.",
                       action: "See modeling assumptions", run: { store.sheet = .assumptions })
                lesson("Know what your fund does", icon: "building.columns",
                       body: "A target-date fund follows a glide path: more stocks early, more bonds near retirement. ARM leaves the allocation as it is.",
                       yours: "Your illustrative allocation holds about \(pct(profile.equityWeight)) stocks today.",
                       action: "Compare funds", run: { store.tab = .funds })
                Text(Disclosure.fictional)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textCaption)
                    .padding(.top, Space.s)
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.page.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Learn", isScrolled: true) { HeaderAvatarButton() }
        }
    }

    private func openStyle(_ style: API.PlanningPreference) {
        store.setPlanStyle(style)
        store.openStyleGuide()
    }

    private func pct(_ value: Double) -> String { SheetCopy.percent(value) }

    private func lesson(_ title: String, icon: String, body: String, yours: String,
                        action: String?, run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Palette.accent)
                .frame(height: 30)
            Text(title).font(TypeScale.headline).foregroundStyle(Palette.textPrimary)
            Text(body).font(TypeScale.body).foregroundStyle(Palette.textSecondary)
            Label(yours, systemImage: "person")
                .font(TypeScale.callout)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
            if let action {
                Button(action: run) {
                    HStack { Text(action); Image(systemName: "arrow.right") }
                        .font(TypeScale.labelMedium)
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressableStyle())
            } else {
                Text("No match to apply").font(TypeScale.caption).foregroundStyle(Palette.textCaption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Palette.hairline, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}
