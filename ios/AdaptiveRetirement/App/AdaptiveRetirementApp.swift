import SwiftUI

@main
struct AdaptiveRetirementApp: App {
    @StateObject private var store = AppStore()

    init() {
        FontRegistry.registerAll()
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.page.ignoresSafeArea()

            switch store.phase {
            case .splash, .onboarding:
                SetupFlowView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(Motion.respecting(reduceMotion, .easeInOut(duration: 0.35)), value: store.phase == .main)
        .sensoryFeedback(trigger: store.phase) { _, new in new == .main ? .success : nil }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: AppStore
    @State private var chatMessages: [EducationMessage] = []
    @State private var chatDraft = ""

    private var chatContext: EducationScreenContext {
        let p = store.displayProfile
        let screen: String
        switch store.tab {
        case .overview: screen = "overview"
        case .plan: screen = "plan"
        case .explore: screen = "explore"
        case .funds: screen = "funds"
        case .learn: screen = "learn"
        }
        let mode: String
        switch store.dataMode {
        case .live: mode = "live"
        case .saved: mode = "saved"
        case .lastLive: mode = "lastLive"
        case .preview: mode = "preview"
        }
        var facts = [
            EducationScreenFact(label: "customer", value: p.name),
            EducationScreenFact(label: "current_age", value: String(p.age)),
            EducationScreenFact(label: "planned_retirement_age", value: String(p.retirementAge))
        ]
        if store.tab != .funds {
            facts += [
                EducationScreenFact(label: "retirement_savings", value: Money.exact(p.retirementBalanceCents)),
                EducationScreenFact(label: "employee_monthly_contribution", value: Money.exact(p.employeeMonthlyCents)),
                EducationScreenFact(label: "employee_contribution_rate", value: String(format: "%.1f%%", p.adaptiveEmployeeRate * 100)),
                EducationScreenFact(label: "employer_monthly_match", value: Money.exact(p.employerMonthlyCents)),
                EducationScreenFact(label: "emergency_savings", value: Money.exact(p.emergencyCashCents)),
                EducationScreenFact(label: "emergency_months", value: String(format: "%.1f", p.emergencyMonths)),
                EducationScreenFact(label: "next_step", value: String(p.primaryActionTitle.prefix(120))),
                EducationScreenFact(label: "next_step_detail", value: String(p.primaryActionDetail.prefix(120))),
                EducationScreenFact(label: "employer_match_captured", value: String(p.matchCaptured)),
                EducationScreenFact(label: "plan_source", value: p.origin.rawValue)
            ]
            if let current = p.evaluation?.projections.current.retirementBalanceTodayCents {
                facts.append(EducationScreenFact(label: "current_projected_retirement_balance", value: Money.exact(current)))
            }
            if let adaptive = p.evaluation?.projections.adaptive.retirementBalanceTodayCents {
                facts.append(EducationScreenFact(label: "adaptive_projected_retirement_balance", value: Money.exact(adaptive)))
            }
        }
        if store.tab == .plan {
            facts.append(EducationScreenFact(label: "stock_allocation", value: String(format: "%.1f%%", p.equityWeight * 100)))
            for priority in p.cashPriorities {
                let kind: String
                switch priority.kind {
                case .retirement: kind = "retirement"
                case .debt: kind = "debt"
                case .emergency: kind = "emergency"
                case .remaining: kind = "remaining"
                }
                facts.append(EducationScreenFact(label: "monthly_\(kind)_priority", value: Money.exact(priority.amountCents)))
            }
            for (index, debt) in p.debts.prefix(3).enumerated() {
                let key = "debt_\(index + 1)"
                facts += [
                    EducationScreenFact(label: "\(key)_type", value: debt.name),
                    EducationScreenFact(label: "\(key)_balance", value: Money.exact(debt.balanceCents)),
                    EducationScreenFact(label: "\(key)_apr", value: String(format: "%.1f%%", debt.apr * 100)),
                    EducationScreenFact(label: "\(key)_monthly_extra", value: Money.exact(debt.extraCents))
                ]
            }
        }
        facts += store.chatScreenFacts[store.tab] ?? []
        return EducationScreenContext(screen: screen, dataMode: mode, facts: Array(facts.prefix(40)))
    }

    var body: some View {
        TabView(selection: $store.tab) {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "circle.grid.2x2") }
                .tag(MainTab.overview)
            PlanView()
                .tabItem { Label("Plan", systemImage: "list.bullet.rectangle") }
                .tag(MainTab.plan)
            ExploreView()
                .tabItem { Label("Explore", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(MainTab.explore)
            FundsView()
                .tabItem { Label("Funds", systemImage: "chart.pie") }
                .tag(MainTab.funds)
            LearnView()
                .tabItem { Label("Learn", systemImage: "book.closed") }
                .tag(MainTab.learn)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                store.sheet = .educationChat
            } label: {
                Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                    .font(TypeScale.labelMedium)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Palette.sheet, in: Capsule())
                    .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            }
            .accessibilityLabel("Ask a retirement question")
            .padding(.trailing, Space.gutter)
            .padding(.bottom, 60)
            .ignoresSafeArea(.keyboard)
        }
        .sensoryFeedback(.selection, trigger: store.tab)
        .onChange(of: store.profile.id) { _, _ in
            chatMessages = []
            chatDraft = ""
            store.presentGuideIfNeeded()
        }
        .onAppear { store.presentGuideIfNeeded() }
        .sheet(item: $store.sheet, onDismiss: { store.presentGuideIfNeeded() }) { sheet in
            switch sheet {
            case .profilePicker: ProfilePickerSheet().presentationDetents([.large])
            case .snapshot: SnapshotSheet().presentationDetents([.large])
            case .explanation: ExplanationSheet().presentationDetents([.large])
            case .assumptions: AssumptionsSheet().presentationDetents([.medium, .large])
            case .accountPreview: AccountPreviewSheet().presentationDetents([.large])
            case .educationChat: EducationChatView(messages: $chatMessages, draft: $chatDraft, context: chatContext).presentationDetents([.large])
            case .gettingStarted: GettingStartedView().presentationDetents([.large])
            case .manualProfile: ManualProfileView().presentationDetents([.large])
            }
        }
    }
}

enum Appearance {
    static func configure() {
        let geist = { (size: CGFloat, name: String) in UIFont(name: name, size: size) ?? .systemFont(ofSize: size) }

        let tab = UITabBarItem.appearance()
        tab.setTitleTextAttributes([.font: geist(10, "Geist-Medium")], for: .normal)

        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.font: geist(17, "Geist-Medium"), .foregroundColor: UIColor(Palette.textPrimary)]
        nav.largeTitleTextAttributes = [.font: geist(32, "Geist-Medium"), .foregroundColor: UIColor(Palette.textPrimary)]

        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([.font: geist(13, "Geist-Regular")], for: .normal)
        seg.setTitleTextAttributes([.font: geist(13, "Geist-Medium")], for: .selected)
    }
}
