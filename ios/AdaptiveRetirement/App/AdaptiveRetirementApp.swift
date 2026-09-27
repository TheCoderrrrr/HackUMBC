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
        }
        .sensoryFeedback(.selection, trigger: store.tab)
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .profilePicker: ProfilePickerSheet().presentationDetents([.large])
            case .snapshot: SnapshotSheet().presentationDetents([.large])
            case .explanation: ExplanationSheet().presentationDetents([.large])
            case .assumptions: AssumptionsSheet().presentationDetents([.medium, .large])
            case .accountPreview: AccountPreviewSheet().presentationDetents([.large])
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
