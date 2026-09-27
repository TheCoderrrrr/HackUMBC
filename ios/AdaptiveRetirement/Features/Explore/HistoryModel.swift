import Foundation

/// Scenario history (Tiger Data): save the result on screen, then compare two saved runs of
/// the same profile over time. The server re-runs the engine for every save and returns
/// every number; this only sends inputs and keeps answers.
@MainActor
final class HistoryModel: ObservableObject {
    enum Phase: Equatable {
        /// No server, history not set up, or its database is down: one sentence says which.
        case unavailable(String)
        case checking
        case ready
    }

    @Published private(set) var phase: Phase = .checking
    @Published private(set) var runs: [API.History.RunSummary] = []
    @Published var basePick: String?
    @Published var otherPick: String?
    @Published private(set) var comparison: RemoteLoad<API.History.Comparison> = .idle
    @Published private(set) var isSaving = false
    /// Result of the last save or list/compare failure, shown under the save row.
    @Published private(set) var note: String?

    /// Bumped on every profile or server change, so late answers for the old one are dropped.
    private var generation = 0

    /// Both picks, for `.task(id:)`: comparing reruns whenever either changes.
    var pairKey: String { "\(basePick ?? "")|\(otherPick ?? "")" }

    func refresh(profileID: String, client: APIClient?) async {
        generation += 1
        let current = generation
        runs = []
        basePick = nil
        otherPick = nil
        comparison = .idle
        note = nil
        guard let client else {
            phase = .unavailable("Connect to the live server to save and compare runs.")
            return
        }
        phase = .checking
        do {
            let status = try await client.historyStatus()
            guard current == generation else { return }
            if !status.enabled {
                phase = .unavailable("Scenario history isn't set up on this server.")
            } else if !status.available {
                phase = .unavailable("Scenario history is unavailable right now. Saved results still work.")
            } else {
                phase = .ready
                await loadRuns(profileID: profileID, client: client, select: nil, generation: current)
            }
        } catch {
            guard current == generation else { return }
            phase = .unavailable(APIError.userMessage(for: error))
        }
    }

    /// Saves the shown result's inputs; the server rebuilds and checks it before storing.
    func save(evaluation: API.Evaluation, scenario: API.Scenario?,
              planningPreference: API.PlanningPreference, client: APIClient?) async {
        guard let client, phase == .ready, !isSaving else { return }
        let current = generation
        isSaving = true
        note = nil
        defer { if current == generation { isSaving = false } }
        let request = API.History.SaveRunRequest(profileID: evaluation.profileID, scenario: scenario,
                                                 decisionSummary: evaluation.decisionSummary,
                                                 inputHash: evaluation.inputHash,
                                                 planningPreference: planningPreference)
        do {
            let response = try await client.saveRun(request)
            guard current == generation else { return }
            note = response.created ? "Saved “\(response.run.label)”." : "“\(response.run.label)” is already in history."
            await loadRuns(profileID: evaluation.profileID, client: client, select: response.run.runID, generation: current)
        } catch {
            guard current == generation else { return }
            note = APIError.userMessage(for: error)
        }
    }

    func compare(client: APIClient?) async {
        guard let client, let base = basePick, let other = otherPick, base != other else {
            comparison = .idle
            return
        }
        let current = generation
        comparison = .loading
        do {
            let result = try await client.compare(base: base, other: other)
            guard current == generation, basePick == base, otherPick == other else { return }
            comparison = .loaded(result)
        } catch {
            guard current == generation, basePick == base, otherPick == other else { return }
            comparison = .failed(APIError.userMessage(for: error))
        }
    }

    /// Newest first. Keeps valid picks; otherwise "with" is the newest (or the just-saved run)
    /// and "Compare" the next one, as on the desktop.
    private func loadRuns(profileID: String, client: APIClient, select saved: String?, generation current: Int) async {
        do {
            let list = try await client.runs(profileID: profileID).runs
            guard current == generation else { return }
            runs = list
            let ids = Set(list.map(\.runID))
            let other = saved.flatMap { ids.contains($0) ? $0 : nil }
                ?? otherPick.flatMap { ids.contains($0) ? $0 : nil }
                ?? list.first?.runID
            let base = basePick.flatMap { ids.contains($0) && $0 != other ? $0 : nil }
                ?? list.first(where: { $0.runID != other })?.runID
            otherPick = other
            basePick = base
        } catch {
            guard current == generation else { return }
            note = APIError.userMessage(for: error)
        }
    }
}
