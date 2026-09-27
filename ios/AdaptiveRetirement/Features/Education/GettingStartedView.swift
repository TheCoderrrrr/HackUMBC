import SwiftUI

/// Five-page guide from the web app, presented as a native sheet.
struct GettingStartedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0
    @State private var picked: API.PlanningPreference = .balanced

    private let titles = [
        "A retirement plan that fits your real finances",
        "Your money goes out in a set order",
        "What matters most early on",
        "Choose your plan style",
        "Where to find things"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Getting started").font(TypeScale.labelMedium)
                Spacer()
                Button("Close", systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Close Getting started")
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Space.xl)
            .frame(height: 56)

            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(index <= step ? Palette.accent : Palette.raised).frame(height: 4)
                }
            }
            .padding(.horizontal, Space.xl)
            .accessibilityLabel("Step \(step + 1) of 5")

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("\(eyebrow) · \(step + 1) of 5")
                        .font(TypeScale.eyebrow)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.accent)
                    Text(titles[step])
                        .font(TypeScale.title2)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    page
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.xl)
            }
            .scrollIndicators(.hidden)

            HStack {
                Button(step == 0 ? "Skip for now" : "Back") {
                    if step == 0 { close() } else { step -= 1 }
                }
                .font(TypeScale.labelMedium)
                .foregroundStyle(Palette.textSecondary)
                .frame(minHeight: 48)
                Spacer()
                Button(primaryTitle) {
                    if step == 4 { finish() } else { step += 1 }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
        }
        .background(Palette.page.ignoresSafeArea())
        .onAppear {
            picked = store.planStyle
            if store.guideStartsAtStyle { step = 3 }
        }
        .onDisappear { store.finishGuide() }
        .onChange(of: store.profile.id) { _, _ in
            step = 0
            picked = store.planStyle
        }
        .task(id: store.profile.id) { await store.loadPlanStyles() }
    }

    private var eyebrow: String {
        ["Welcome, \(store.displayProfile.name)", "How ARM decides", "Three ideas", "Your plan style", "You're set"][step]
    }

    private var primaryTitle: String {
        ["Show me how it works", "Next", "Choose my style", "Use \(picked.label)", "Open my plan"][step]
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0:
            Text("ARM keeps your target-date fund as it is. It adapts how much you save and where each extra dollar goes. This guide takes about two minutes.")
                .font(TypeScale.body)
            guideRow("How ARM decides where your money goes", icon: "list.number")
            guideRow("The three ideas that matter most", icon: "checkmark.seal")
            guideRow("Choosing your plan style", icon: "slider.horizontal.3")
            Button("Prefer to read first? Start in Learn") {
                store.finishGuide()
                store.tab = .learn
            }
            .font(TypeScale.labelMedium)
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 48)
        case 1:
            Text("Each month, ARM covers these in order. You choose how step 4 balances the goals.")
                .font(TypeScale.body)
            guideRow("1. Essentials and minimum payments", detail: "Rent, food, bills and every debt's minimum.", icon: "house")
            guideRow("2. A small reserve", detail: "Cash so a minor surprise needn't go on a card.", icon: "banknote")
            guideRow("3. The full employer match", detail: "Employer money, kept whenever you can afford it.", icon: "checkmark.seal")
            guideRow("4. Your plan style", detail: "Orders the cushion, expensive debt and full emergency fund.", icon: "slider.horizontal.3")
            guideRow("5. More retirement saving", detail: savingTarget, icon: "chart.line.uptrend.xyaxis")
            guideRow("6. Anything left is yours", detail: "Spend it, save it or put it toward other goals.", icon: "sparkles")
        case 2:
            Text("ARM handles all three. Your style sets the balance between debt and your safety net.")
                .font(TypeScale.body)
            guideRow("Take the full match", detail: "It's part of your pay. Missing it leaves money behind.", icon: "checkmark.seal")
            guideRow("Clear expensive debt", detail: "High card interest can exceed investment returns.", icon: "flag")
            guideRow("Keep a safety net", detail: "Cash for surprises helps avoid new borrowing.", icon: "umbrella")
        case 3:
            Text("Pick the one that feels right. You can reopen this guide from Learn or Plan.")
                .font(TypeScale.body)
            ForEach(API.PlanningPreference.allCases, id: \.self) { style in
                Button { picked = style } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: picked == style ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(picked == style ? Palette.accent : Palette.textCaption)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(style.label).font(TypeScale.labelMedium)
                            Text(style.summary).font(TypeScale.caption).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                    }
                    .foregroundStyle(Palette.textPrimary)
                    .padding(Space.l)
                    .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(picked == style ? [.isSelected] : [])
            }
            Text(picked.detail)
                .font(TypeScale.callout)
                .foregroundStyle(Palette.textSecondary)
            guideRow("Why people choose it", detail: picked.benefit, icon: "checkmark")
            guideRow("What you give up", detail: picked.tradeoff, icon: "arrow.turn.down.right")
            if let outcome = store.planStyles?.styles.first(where: { $0.style == picked }) {
                if let priorities = outcome.orderedPriorities {
                    Text("Where extra money goes, in order")
                        .font(TypeScale.labelMedium)
                        .foregroundStyle(Palette.textPrimary)
                    ForEach(Array(priorities.enumerated()), id: \.offset) { index, priority in
                        guideRow("\(index + 1). \(priority.label)", icon: "arrow.down")
                    }
                }
                guideRow("High-interest debt paid off",
                         detail: milestone(outcome.debtFreeMonth, zero: "No debt", missing: "After retirement"),
                         icon: "flag")
                guideRow("Emergency fund full",
                         detail: milestone(outcome.fullReserveMonth, zero: "Already", missing: "Not reached"),
                         icon: "umbrella")
            } else if let message = store.planStylesMessage {
                Text(message)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textCaption)
            } else {
                ProgressView("Working out your numbers…")
                    .font(TypeScale.caption)
            }
            if store.planStyle != store.savedPlanStyle && store.dataMode != .live {
                Text("The saved calculation uses \(store.savedPlanStyle.label). Your selected style needs a live calculation.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textCaption)
            }
        default:
            Text("You're set. Open each part of the app whenever you need it.")
                .font(TypeScale.body)
            guideRow("Overview", detail: "Your next step and where you stand today.", icon: "circle.grid.2x2")
            guideRow("Your plan", detail: "Contributions, priorities, debt and savings.", icon: "list.bullet.rectangle")
            guideRow("Explore", detail: "Try another retirement age or contribution.", icon: "chart.line.uptrend.xyaxis")
            guideRow("Funds", detail: "Compare target-date funds.", icon: "chart.pie")
            guideRow("Learn", detail: "Short lessons applied to your numbers.", icon: "book.closed")
            guideRow("Ask", detail: "Ask a retirement question from any tab.", icon: "bubble.left.and.text.bubble.right")
        }
    }

    private var savingTarget: String {
        let value = store.displayProfile.evaluation?.assumptions.retirementTotalSavingTarget
            ?? ModelAssumptions.illustrative.retirementTotalSavingTarget
        return "Toward a combined saving rate of \(SheetCopy.percent(value)) of pay."
    }

    private func milestone(_ month: Int?, zero: String, missing: String) -> String {
        guard let month else { return missing }
        if month == 0 { return zero }
        guard let asOf = store.planStyles?.asOfDate,
              let date = ISO8601DateFormatter().date(from: asOf + "T00:00:00Z"),
              let target = Calendar(identifier: .gregorian).date(byAdding: .month, value: month, to: date) else {
            return "Month \(month)"
        }
        return target.formatted(.dateTime.month(.abbreviated).year())
    }

    private func guideRow(_ title: String, detail: String? = nil, icon: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(TypeScale.labelMedium).foregroundStyle(Palette.textPrimary)
                if let detail { Text(detail).font(TypeScale.callout).foregroundStyle(Palette.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(Palette.sheet, in: RoundedRectangle(cornerRadius: 12))
    }

    private func close() { store.finishGuide() }

    private func finish() {
        store.setPlanStyle(picked)
        store.finishGuide()
        store.tab = .plan
    }
}

extension API.PlanningPreference {
    var label: String {
        switch self {
        case .balanced: "Balanced"
        case .cashSecurity: "Cash security first"
        case .debtReduction: "Debt payoff first"
        }
    }

    var summary: String {
        switch self {
        case .balanced: "A bit of both"
        case .cashSecurity: "Safety net first"
        case .debtReduction: "Clear expensive debt fast"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "Balances paying down expensive debt with building an emergency fund, so neither is ignored."
        case .cashSecurity: "Builds a full emergency fund before putting extra money toward debt. Debt interest may last longer."
        case .debtReduction: "Sends extra money to the highest-interest debt before building more savings. Your cash cushion stays smaller until the debt is gone."
        }
    }

    var benefit: String {
        switch self {
        case .balanced: "You make steady progress on debt and savings while a cash cushion grows."
        case .cashSecurity: "You set aside months of expenses sooner, which can help when income is uncertain."
        case .debtReduction: "Paying the most expensive debt sooner usually saves the most interest."
        }
    }

    var tradeoff: String {
        switch self {
        case .balanced: "Splitting extra money means neither goal finishes as quickly."
        case .cashSecurity: "Expensive debt may last longer and cost more interest."
        case .debtReduction: "Your cash cushion stays smaller until the debt is gone."
        }
    }
}

extension API.Priority {
    var label: String {
        switch self {
        case .starterReserve: "One-month cushion"
        case .highAprDebt: "High-interest debt"
        case .fullReserve: "Full emergency fund"
        }
    }
}
