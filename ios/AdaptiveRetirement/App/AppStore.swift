import SwiftUI

enum AppPhase: Equatable {
    case splash
    case onboarding
    case main
}

enum OnboardingStep: Int, CaseIterable, Comparable {
    case profile, accounts, focus, result
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

enum MainTab: Hashable {
    case overview, plan, explore, funds, learn
}

enum ActiveSheet: String, Identifiable {
    case profilePicker, snapshot, explanation, assumptions, accountPreview, educationChat, gettingStarted, manualProfile
    var id: String { rawValue }
}

/// A backend evaluation plus where it came from, so labels never outlive their source.
struct LoadedEvaluation {
    let evaluation: API.Evaluation
    let mode: DataMode
    /// The exact profile the engine evaluated (sent with the request, or bundled with the
    /// artifact), so display inputs come from what the engine saw — not the hand-typed
    /// fixture (REPORT B4). Nil only for DEBUG fixture previews.
    var apiProfile: API.FinancialProfile? = nil

    var origin: DecisionOrigin {
        switch evaluation.decisionSummary.source {
        case .rulesFallback: return .rules
        case .ai: return mode == .saved ? .savedAI : .ai
        }
    }

    func relabeled(_ mode: DataMode) -> LoadedEvaluation {
        LoadedEvaluation(evaluation: evaluation, mode: mode, apiProfile: apiProfile)
    }
}

/// FRONTEND.md §5 loading state. `previous` stays on screen during refresh and after failure.
enum EvaluationLoad {
    case idle
    case loading(previous: LoadedEvaluation?)
    case loaded(LoadedEvaluation)
    case failed(previous: LoadedEvaluation?, error: Error)

    var current: LoadedEvaluation? {
        switch self {
        case .idle: return nil
        case .loading(let previous), .failed(let previous, _): return previous
        case .loaded(let loaded): return loaded
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Root presentation state. Holds no financial policy.
@MainActor
final class AppStore: ObservableObject {
    @Published var phase: AppPhase = .splash
    @Published var onboardingStep: OnboardingStep = .profile
    @Published var focus: Focus = .debt
    @Published var profile: Profile = .morgan
    @Published private(set) var manualProfile: API.FinancialProfile?
    @Published var tab: MainTab = .overview
    @Published var chatScreenFacts: [MainTab: [EducationScreenFact]] = [:]
    @Published var sheet: ActiveSheet?
    @Published var pendingLearnScenario: ScenarioDraft?
    @Published private(set) var planStyle: API.PlanningPreference = .balanced
    @Published var guideStartsAtStyle = false
    @Published private(set) var planStyles: API.PlanStyles?
    @Published private(set) var planStylesMessage: String?
    /// Explore's "Drag to a date" hint shows once after onboarding.
    @Published var showsPlayheadHint = true

    /// Backend evaluation for `profile`. `.idle` until a bundle or server supplies one.
    @Published private(set) var evaluationLoad: EvaluationLoad = .idle
    /// Public HTTPS base URL, e.g. the ngrok tunnel. Empty means saved data only.
    @Published private(set) var serverBaseURL: String
    /// Bumped whenever the server changes, so Funds and History reload against the new one.
    @Published private(set) var serverGeneration = 0

    static let serverBaseURLKey = "serverBaseURL"
    /// Build-time default from the `ServerBaseURL` Info.plist key (set by
    /// `Config/Server.xcconfig`, overridden by the git-ignored `Signing.local.xcconfig`).
    /// The committed default is empty — saved data only — until someone sets a domain for
    /// the build or saves one in Explore › Modeling assumptions.
    static var defaultServerBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "ServerBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Shared demo key from the `DemoKey` Info.plist key (set by `Config/Server.xcconfig`,
    /// overridden by the git-ignored `Signing.local.xcconfig`). Sent as `X-Demo-Key` when
    /// the demo server requires it (REPORT C2); the committed default is empty.
    static var defaultDemoKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "DemoKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private let demo: DemoRepository
    private var client: APIClient?
    private var selectionGeneration = 0
    private var evaluationTask: Task<Void, Never>?
    private var lastLive: [String: LoadedEvaluation] = [:]
    private var lastLiveDecision: (profileID: String, decisionID: String)?
    private var serverProfiles: [String: API.FinancialProfile] = [:]
    private let defaults: UserDefaults

    /// `client` overrides the URL-based client (previews and tests).
    init(demo: DemoRepository = DemoRepository(), client: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.demo = demo
        self.defaults = defaults
        if let data = defaults.data(forKey: "manualProfile"),
           let saved = try? JSONDecoder().decode(API.FinancialProfile.self, from: data) {
            self.manualProfile = saved
            self.profile = .personal(saved)
        }
        let url = defaults.string(forKey: Self.serverBaseURLKey) ?? Self.defaultServerBaseURL
        self.serverBaseURL = url
        self.client = client ?? LiveAPIClient(baseURLString: url, demoKey: Self.defaultDemoKey)
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
        planStyle = savedStyle(for: profile.id)
        refreshEvaluation()
    }

    #if DEBUG
    /// `-evaluationFixtures <dir>` treats `<dir>/evaluate-<profile>.response.json` (for example
    /// the repo's `contracts/examples`) as the saved result, to preview engine data without a bundle.
    private func debugFixtureEvaluation(for profileID: String) -> LoadedEvaluation? {
        guard let dir = UserDefaults.standard.string(forKey: "evaluationFixtures") else { return nil }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("evaluate-\(profileID).response.json")
        guard let data = try? Data(contentsOf: url),
              let evaluation = try? JSONDecoder().decode(API.Evaluation.self, from: data),
              evaluation.profileID == profileID else { return nil }
        return LoadedEvaluation(evaluation: evaluation, mode: .saved)
    }

    /// `-screen <name>` jumps straight to a screen for previews and screenshots:
    /// splash, profile, accounts, focus, result, overview, plan, explore,
    /// and sheet names (picker, snapshot, explanation, assumptions, accountPreview).
    /// `-focus debt|cash|retirement`, `-profile morgan|jordan|casey`, `-hint 0`,
    /// `-serverBaseURL https://…` (read in `init`), `-evaluationFixtures <dir>`.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "profile"), let p = Profile.all.first(where: { $0.id == id }) { profile = p }
        if let f = defaults.string(forKey: "focus"), let value = Focus(rawValue: f) { focus = value }
        if defaults.object(forKey: "hint") != nil { showsPlayheadHint = defaults.bool(forKey: "hint") }
        guard let screen = defaults.string(forKey: "screen") else { return }
        switch screen {
        case "splash": phase = .splash
        case "profile": phase = .onboarding; onboardingStep = .profile
        case "accounts": phase = .onboarding; onboardingStep = .accounts
        case "focus": phase = .onboarding; onboardingStep = .focus
        case "result": phase = .onboarding; onboardingStep = .result
        case "overview": phase = .main; tab = .overview
        case "plan": phase = .main; tab = .plan
        case "explore": phase = .main; tab = .explore
        case "funds": phase = .main; tab = .funds
        case "learn": phase = .main; tab = .learn
        case "gettingStarted": phase = .main; tab = .learn; sheet = .gettingStarted
        case "picker": phase = .main; sheet = .profilePicker
        case "snapshot": phase = .main; sheet = .snapshot
        case "explanation": phase = .main; sheet = .explanation
        case "assumptions": phase = .main; tab = .explore; sheet = .assumptions
        case "accountPreview": phase = .onboarding; onboardingStep = .profile; sheet = .accountPreview
        default: break
        }
    }
    #endif

    /// What screens render: the fixture with the current evaluation applied, or the plain
    /// `DemoData` fixture while `evaluationLoad` is `.idle`.
    var displayProfile: Profile { profile.applying(evaluationLoad.current) }

    /// Label for what is on screen, derived from the load state so it can never outlive
    /// its source: a live/saved calculation, or "Illustrative preview" while the screens
    /// show hand-typed fixture values — including during the first load (REPORT B1).
    var dataMode: DataMode {
        switch evaluationLoad {
        case .idle: return .preview
        case .loading(let previous), .failed(let previous, _): return previous?.mode ?? .preview
        case .loaded(let loaded): return loaded.mode
        }
    }

    /// The current evaluation failure with a short message, surfaced for every failure —
    /// not just retryable ones — so a dead server never fails silently (REPORT B10).
    /// Retry is always offered: it is a manual re-request, not an automatic one.
    var evaluationFailure: (message: String, error: Error)? {
        guard case .failed(_, let error) = evaluationLoad else { return nil }
        if let api = error as? APIError {
            switch api {
            case .cancelled: return nil
            case .timedOut: return ("The calculation took too long.", error)
            case .unreachable, .invalidBaseURL: return ("Couldn't reach the server.", error)
            case .server(_, let body): return (body.message, error)
            case .unexpectedStatus(let status): return ("The server answered with an error (\(status)).", error)
            case .invalidResponse: return ("The server's answer didn't match what the app expects.", error)
            }
        }
        return ("Something went wrong.", error)
    }

    func select(_ profile: Profile) {
        guard profile.id != self.profile.id else { return }
        self.profile = profile
        planStyle = savedStyle(for: profile.id)
        pendingLearnScenario = nil
        planStyles = nil
        planStylesMessage = nil
        chatScreenFacts = [:]
        lastLiveDecision = nil
        refreshEvaluation()
    }

    func useManualProfile(_ input: API.FinancialProfile) {
        manualProfile = input
        defaults.set(try? JSONEncoder().encode(input), forKey: "manualProfile")
        profile = .personal(input)
        planStyle = input.planningPreference
        lastLive[profile.id] = nil
        lastLiveDecision = nil
        refreshEvaluation()
    }

    private func savedStyle(for id: String) -> API.PlanningPreference {
        if let raw = defaults.string(forKey: "planStyle.\(id)"), let style = API.PlanningPreference(rawValue: raw) {
            return style
        }
        return (try? demo.profiles()[id]?.planningPreference) ?? .balanced
    }

    var savedPlanStyle: API.PlanningPreference {
        evaluationLoad.current?.apiProfile?.planningPreference ?? .balanced
    }

    func setPlanStyle(_ style: API.PlanningPreference) {
        guard style != planStyle else { return }
        planStyle = style
        defaults.set(style.rawValue, forKey: "planStyle.\(profile.id)")
        lastLive[profile.id] = nil
        lastLiveDecision = nil
        refreshEvaluation()
    }

    func openStyleGuide() {
        guideStartsAtStyle = true
        sheet = .gettingStarted
    }

    func presentGuideIfNeeded() {
        guard !defaults.bool(forKey: "gettingStartedSeen.\(profile.id)"), sheet == nil else { return }
        sheet = .gettingStarted
    }

    func finishGuide() {
        defaults.set(true, forKey: "gettingStartedSeen.\(profile.id)")
        guideStartsAtStyle = false
        sheet = nil
    }

    func tryLearnScenario(retirementAge: Int, rate: Double?) {
        var next = ScenarioDraft.original(for: displayProfile)
        next.retirementAge = retirementAge
        if let rate {
            next.policy = .fixed
            next.fixedRate = rate * 100
        }
        next.preset = nil
        pendingLearnScenario = next
        showsPlayheadHint = false
        tab = .explore
    }

    func loadPlanStyles() async {
        guard let client else {
            planStyles = nil
            planStylesMessage = "Turn on live calculation to compare your styles."
            return
        }
        let id = profile.id
        let generation = serverGeneration
        do {
            let base = try await apiProfile(for: id, client: client)
            let response = try await client.planStyles(base)
            guard id == profile.id, generation == serverGeneration else { return }
            planStyles = response
            planStylesMessage = nil
        } catch {
            guard id == profile.id, generation == serverGeneration else { return }
            planStyles = nil
            planStylesMessage = APIError.userMessage(for: error)
        }
    }

    // MARK: Backend evaluation

    var isLiveEnabled: Bool { client != nil }

    /// The configured client for the Funds and History screens; nil means saved data only.
    var apiClient: APIClient? { client }

    /// Changing the server resets live state but keeps bundled profiles (FRONTEND.md §8).
    /// Returns false, and changes nothing, unless the URL is empty or absolute HTTPS.
    @discardableResult
    func setServerBaseURL(_ string: String, defaults: UserDefaults = .standard) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let newClient = LiveAPIClient(baseURLString: trimmed, demoKey: Self.defaultDemoKey)
        guard trimmed.isEmpty || newClient != nil else { return false }
        serverBaseURL = trimmed
        defaults.set(trimmed, forKey: Self.serverBaseURLKey)
        client = newClient
        serverGeneration += 1
        lastLive = [:]
        lastLiveDecision = nil
        serverProfiles = [:]
        planStyles = nil
        planStylesMessage = nil
        refreshEvaluation()
        return true
    }

    /// Shows the saved result immediately, then requests a live one if a server is configured.
    func refreshEvaluation() {
        selectionGeneration += 1
        let generation = selectionGeneration
        evaluationTask?.cancel()
        let profileID = profile.id

        let saved = savedEvaluation(for: profileID)
        let previous = lastLive[profileID]?.relabeled(.lastLive) ?? saved
        guard let client else {
            evaluationLoad = saved.map(EvaluationLoad.loaded) ?? .idle
            return
        }
        evaluationLoad = .loading(previous: previous)

        evaluationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let apiProfile = try await self.apiProfile(for: profileID, client: client)
                var styledProfile = apiProfile
                styledProfile.planningPreference = self.planStyle
                let previousID = self.lastLiveDecision?.profileID == profileID ? self.lastLiveDecision?.decisionID : nil
                let evaluation = try await client.evaluate(
                    API.EvaluateRequest(profile: styledProfile, scenario: nil, previousDecisionID: previousID)
                )
                guard generation == self.selectionGeneration, evaluation.profileID == profileID else { return }
                let loaded = LoadedEvaluation(evaluation: evaluation, mode: .live, apiProfile: styledProfile)
                self.lastLive[profileID] = loaded
                self.lastLiveDecision = (profileID, evaluation.decisionSummary.decisionID)
                self.evaluationLoad = .loaded(loaded)
            } catch {
                guard generation == self.selectionGeneration, !Self.isCancellation(error) else { return }
                self.evaluationLoad = .failed(previous: previous, error: error)
            }
        }
    }

    /// Live custom scenario for the current profile. Throws `APIError.unreachable` offline,
    /// where the UI shows "Reconnect for a custom scenario" and offers saved presets instead.
    func evaluateScenario(_ scenario: API.Scenario) async throws -> LoadedEvaluation {
        guard let client else { throw APIError.unreachable }
        let profileID = profile.id
        let apiProfile = try await apiProfile(for: profileID, client: client)
        var styledProfile = apiProfile
        styledProfile.planningPreference = planStyle
        let previousID = lastLiveDecision?.profileID == profileID ? lastLiveDecision?.decisionID : nil
        let evaluation = try await client.evaluate(
            API.EvaluateRequest(profile: styledProfile, scenario: scenario, previousDecisionID: previousID,
                                baseDecisionID: lastLive[profileID]?.evaluation.decisionSummary.decisionID)
        )
        // Scenario decisions deliberately stay out of lastLiveDecision: the next base
        // refresh must diff against the base plan's decision, not a scenario's (REPORT E1).
        return LoadedEvaluation(evaluation: evaluation, mode: .live, apiProfile: styledProfile)
    }

    /// Exact saved artifact, or nil until Eric's bundle is in `Resources/Demo/`.
    func savedEvaluation(for profileID: String, preset: DemoPreset = .original) -> LoadedEvaluation? {
        #if DEBUG
        if preset == .original, let fixture = debugFixtureEvaluation(for: profileID) { return fixture }
        #endif
        guard let artifact = try? demo.artifact(profileID: profileID, preset: preset) else { return nil }
        return LoadedEvaluation(evaluation: artifact.evaluation, mode: .saved,
                                apiProfile: try? demo.profiles()[profileID])
    }

    /// The saved artifact itself, for callers that also need the scenario it was exported with.
    func savedArtifact(for profileID: String, preset: DemoPreset) -> DemoArtifact? {
        try? demo.artifact(profileID: profileID, preset: preset)
    }

    private func apiProfile(for id: String, client: APIClient) async throws -> API.FinancialProfile {
        if id == manualProfile?.id, let manualProfile { return manualProfile }
        if let bundled = try? demo.profiles()[id] { return bundled }
        if serverProfiles.isEmpty {
            let response = try await client.demoProfiles()
            serverProfiles = Dictionary(response.profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        guard let profile = serverProfiles[id] else { throw APIError.invalidResponse }
        return profile
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? APIError) == .cancelled
    }

    func finishOnboarding() {
        tab = .explore
        showsPlayheadHint = true
        phase = .main
    }

    func replayOnboarding() {
        onboardingStep = .profile
        focus = .debt
        phase = .onboarding
    }
}
