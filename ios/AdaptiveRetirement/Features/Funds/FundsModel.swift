import Foundation

/// A request's state on the Funds and History screens.
enum RemoteLoad<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Inputs and results for the fund shortlist. Holds no ranking logic: the server filters,
/// scores and explains; this only sends the user's choices and keeps the answer.
@MainActor
final class FundsModel: ObservableObject {
    // Changing any input clears the shown result, so a shortlist never outlives its inputs.
    @Published var account: API.Funds.AccountType = .k401 { didSet { inputsChanged() } }
    @Published var risk: API.Funds.RiskTolerance = .moderate { didSet { inputsChanged() } }
    @Published var retirementYear: Int = Calendar.current.component(.year, from: .now) { didSet { inputsChanged() } }
    @Published var menuKnown = false { didSet { inputsChanged() } }
    @Published var menu: Set<String> = [] { didSet { inputsChanged() } }

    @Published private(set) var catalog: RemoteLoad<API.Funds.CatalogSummary> = .idle
    @Published private(set) var shortlist: RemoteLoad<API.Funds.Envelope> = .idle

    private var requestID = 0

    /// The server accepts this year through 60 years from now, by its own clock.
    var yearRange: ClosedRange<Int> {
        let now = Calendar.current.component(.year, from: .now)
        return now...(now + 60)
    }

    /// New profile or server: default the year to the profile's retirement year and drop
    /// the old result (the desktop keeps it, which can show another customer's shortlist).
    func reset(retirementYear year: Int) {
        requestID += 1
        retirementYear = min(max(year, yearRange.lowerBound), yearRange.upperBound)
        shortlist = .idle
    }

    func loadCatalog(client: APIClient?) async {
        guard let client else { catalog = .idle; return }
        if catalog.value != nil || catalog.isLoading { return }
        catalog = .loading
        do {
            catalog = .loaded(try await client.fundCatalog())
        } catch {
            catalog = .failed(APIError.userMessage(for: error))
        }
    }

    /// The catalog must reload after a server change.
    func forgetCatalog() {
        catalog = .idle
        menu = []
    }

    func requestShortlist(client: APIClient?) {
        guard let client else {
            shortlist = .failed("Fund shortlist needs the live server. Saved plans still work.")
            return
        }
        requestID += 1
        let id = requestID
        let query = API.Funds.Query(
            accountType: account, retirementYear: retirementYear, riskTolerance: risk,
            planMenuFundIDs: account == .k401 && menuKnown ? menu.sorted() : nil
        )
        shortlist = .loading
        Task {
            do {
                let envelope = try await client.fundShortlist(query)
                guard id == requestID else { return }
                shortlist = .loaded(envelope)
            } catch {
                guard id == requestID else { return }
                let offline = (error as? APIError).map { $0 == .unreachable || $0 == .invalidBaseURL } ?? false
                shortlist = .failed(offline ? "Couldn't reach the server. The fund shortlist needs the live server; saved plans still work."
                                            : APIError.userMessage(for: error))
            }
        }
    }

    /// Drops any in-flight request and the shown result.
    private func inputsChanged() {
        requestID += 1
        if case .idle = shortlist { return }
        shortlist = .idle
    }
}
