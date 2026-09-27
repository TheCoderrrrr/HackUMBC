import Foundation
import Security

/// Failures the UI can distinguish (FRONTEND.md §5 APIClient, §6 error envelope).
enum APIError: Error, Equatable {
    /// The base URL is missing, malformed, or not HTTPS.
    case invalidBaseURL
    /// The eight-second evaluation deadline (or the shorter request deadline) passed.
    case timedOut
    case cancelled
    /// No connection, DNS failure, TLS failure, or the tunnel is down.
    case unreachable
    /// The backend returned its error envelope (422, 401, 429, 503, sanitized 500).
    case server(status: Int, body: API.ErrorBody)
    /// A non-2xx response without a readable envelope.
    case unexpectedStatus(Int)
    /// The response did not match the contract (wrong schema or corrupt body).
    case invalidResponse

    var isRetryable: Bool {
        switch self {
        case .timedOut, .unreachable: return true
        case .server(_, let body): return body.retryable
        case .unexpectedStatus(let status): return status >= 500
        case .invalidBaseURL, .cancelled, .invalidResponse: return false
        }
    }
}

extension APIError {
    /// Short copy for a failed request on the Funds and History screens. A server envelope is
    /// a real answer, so its own message is shown.
    var userMessage: String {
        switch self {
        case .server(_, let body): return body.message
        case .timedOut: return "The server took too long. Try again."
        case .unreachable, .invalidBaseURL: return "Couldn't reach the server."
        case .unexpectedStatus(let status): return "The server answered with an error (\(status))."
        case .invalidResponse: return "The server's answer didn't match what the app expects."
        case .cancelled: return "The request was cancelled."
        }
    }

    /// `userMessage` for any error, including non-`APIError` failures.
    static func userMessage(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? "Something went wrong."
    }
}

protocol APIClient: Sendable {
    func health() async throws -> API.Health
    func demoProfiles() async throws -> API.DemoProfiles
    func evaluate(_ request: API.EvaluateRequest) async throws -> API.Evaluation
    func planStyles(_ profile: API.FinancialProfile) async throws -> API.PlanStyles
    func buildProfile(_ input: API.ManualProfileInput) async throws -> API.ProfileBuild
    func saveProfile(_ input: API.ManualProfileInput) async throws -> API.ProfileBuild
    func loadProfile() async throws -> API.StoredProfile
    func deleteProfile() async throws

    // Fund shortlist (`backend/app/fund_api.py`)
    func fundCatalog() async throws -> API.Funds.CatalogSummary
    func fundShortlist(_ query: API.Funds.Query) async throws -> API.Funds.Envelope

    // Scenario history on Tiger Data (`backend/app/analytics/router.py`)
    func historyStatus() async throws -> API.History.Status
    func saveRun(_ request: API.History.SaveRunRequest) async throws -> API.History.SaveRunResponse
    func runs(profileID: String) async throws -> API.History.RunList
    func compare(base: String, other: String) async throws -> API.History.Comparison
}

extension APIClient {
    func buildProfile(_ input: API.ManualProfileInput) async throws -> API.ProfileBuild { throw APIError.unreachable }
    func saveProfile(_ input: API.ManualProfileInput) async throws -> API.ProfileBuild { try await buildProfile(input) }
    func loadProfile() async throws -> API.StoredProfile { throw APIError.unreachable }
    func deleteProfile() async throws { throw APIError.unreachable }
}

/// The anonymous credential that owns a manual profile and its history. It is an opaque,
/// random identifier—not an account login—and belongs in Keychain rather than UserDefaults.
/// A one-time migration preserves existing local profiles created before this storage change.
private enum ProfileCredential {
    private static let service = "com.hackumbc.adaptiveretirement"
    private static let account = "anonymous-profile-key"
    private static let legacyDefaultsKey = "arm:profileKey"

    static func loadOrCreate() -> String {
        if let key = read() { return key }
        if let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey), !legacy.isEmpty {
            if save(legacy) {
                UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            }
            return legacy
        }
        let key = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        // Keychain is available on supported iOS versions; if it transiently rejects an
        // item, keep the credential in memory rather than downgrading it into UserDefaults.
        _ = save(key)
        return key
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    private static func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}

/// Marker for an HTTP response that intentionally has no body (for example DELETE 204).
private struct EmptyResponse: Decodable {}

/// URLSession client for the FastAPI backend. Never logs request bodies or tokens.
final class LiveAPIClient: APIClient {
    static let evaluationTimeout: TimeInterval = 8
    static let requestTimeout: TimeInterval = 5

    let baseURL: URL
    /// Shared demo key sent as X-Demo-Key when the server sets DEMO_KEY (REPORT C2).
    private let demoKey: String
    private let session: URLSession
    private let profileKey: String

    /// Returns nil unless `baseURLString` is an absolute HTTPS URL with a host.
    init?(baseURLString: String, demoKey: String = "", session: URLSession = .shared) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        self.baseURL = url
        self.demoKey = demoKey
        self.session = session
        self.profileKey = ProfileCredential.loadOrCreate()
    }

    func health() async throws -> API.Health {
        try await send(path: "health", method: "GET", body: nil, timeout: Self.requestTimeout)
    }

    func demoProfiles() async throws -> API.DemoProfiles {
        try await send(path: "v1/demo-profiles", method: "GET", body: nil, timeout: Self.requestTimeout)
    }

    func evaluate(_ request: API.EvaluateRequest) async throws -> API.Evaluation {
        let body: Data
        do { body = try JSONEncoder().encode(request) } catch { throw APIError.invalidResponse }
        return try await send(path: "v1/evaluate", method: "POST", body: body, timeout: Self.evaluationTimeout)
    }

    func planStyles(_ profile: API.FinancialProfile) async throws -> API.PlanStyles {
        struct Request: Encodable { let profile: API.FinancialProfile }
        return try await send(path: "v1/plan-styles", method: "POST", body: try encoded(Request(profile: profile)),
                              timeout: Self.evaluationTimeout)
    }

    func buildProfile(_ input: API.ManualProfileInput) async throws -> API.ProfileBuild {
        try await send(path: "v1/profiles/build", method: "POST", body: try encoded(input), timeout: Self.requestTimeout)
    }

    func saveProfile(_ input: API.ManualProfileInput) async throws -> API.ProfileBuild {
        try await send(path: "v1/profiles/me", method: "PUT", body: try encoded(input), timeout: Self.requestTimeout)
    }

    func loadProfile() async throws -> API.StoredProfile {
        try await send(path: "v1/profiles/me", method: "GET", body: nil, timeout: Self.requestTimeout)
    }

    func deleteProfile() async throws {
        let _: EmptyResponse = try await send(path: "v1/profiles/me", method: "DELETE",
                                               body: nil, timeout: Self.requestTimeout)
    }

    func fundCatalog() async throws -> API.Funds.CatalogSummary {
        try await send(path: "v1/funds/catalog", method: "GET", body: nil, timeout: Self.requestTimeout)
    }

    func fundShortlist(_ query: API.Funds.Query) async throws -> API.Funds.Envelope {
        try await send(path: "v1/funds/shortlist", method: "POST", body: try encoded(query), timeout: Self.requestTimeout)
    }

    /// The server's status check pings the database with a 5 s connect timeout, so this
    /// gets the longer deadline.
    func historyStatus() async throws -> API.History.Status {
        try await send(path: "v1/history/status", method: "GET", body: nil, timeout: Self.evaluationTimeout)
    }

    /// 201 for a new run, 200 when the same `input_hash` was already saved; `created` says which.
    func saveRun(_ request: API.History.SaveRunRequest) async throws -> API.History.SaveRunResponse {
        try await send(path: "v1/history/runs", method: "POST", body: try encoded(request), timeout: Self.evaluationTimeout)
    }

    func runs(profileID: String) async throws -> API.History.RunList {
        try await send(path: "v1/history/runs", method: "GET", query: [URLQueryItem(name: "profile_id", value: profileID)],
                       body: nil, timeout: Self.requestTimeout)
    }

    func compare(base: String, other: String) async throws -> API.History.Comparison {
        try await send(path: "v1/history/compare", method: "GET",
                       query: [URLQueryItem(name: "base", value: base), URLQueryItem(name: "other", value: other)],
                       body: nil, timeout: Self.requestTimeout)
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        do { return try JSONEncoder().encode(value) } catch { throw APIError.invalidResponse }
    }

    /// Query items go through `URLComponents`: `appendingPathComponent` would percent-encode a `?`.
    private func send<Response: Decodable>(
        path: String, method: String, query: [URLQueryItem] = [], body: Data?, timeout: TimeInterval
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.invalidBaseURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // ngrok's free tier can interpose a browser warning page; this header opts out.
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if !demoKey.isEmpty {
            request.setValue(demoKey, forHTTPHeaderField: "X-Demo-Key")
        }
        request.setValue(profileKey, forHTTPHeaderField: "X-Profile-Key")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw APIError.cancelled
            case .timedOut: throw APIError.timedOut
            default: throw APIError.unreachable
            }
        } catch {
            throw APIError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(API.ErrorEnvelope.self, from: data) {
                throw APIError.server(status: http.statusCode, body: envelope.error)
            }
            debugLogUndecodable(status: http.statusCode, data: data)
            // ngrok answers with an HTML page when the tunnel or the laptop behind it is
            // down (ngrok-error-code header, 404 ERR_NGROK_3200, 502 ERR_NGROK_8012).
            // That is a dead connection, not a server answer: treat as unreachable,
            // which is retryable and eligible for the saved-preset fallback.
            if http.value(forHTTPHeaderField: "ngrok-error-code") != nil
                || [404, 502, 503, 504].contains(http.statusCode) {
                throw APIError.unreachable
            }
            throw APIError.unexpectedStatus(http.statusCode)
        }
        do {
            if data.isEmpty, Response.self == EmptyResponse.self {
                return EmptyResponse() as! Response
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            debugLogUndecodable(status: http.statusCode, data: data)
            throw APIError.invalidResponse
        }
    }

    /// DEBUG-only peek at a failure body (status + first 200 bytes). Response only;
    /// request bodies and tokens are never logged (FRONTEND.md §5).
    private func debugLogUndecodable(status: Int, data: Data) {
        #if DEBUG
        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<\(data.count) non-UTF8 bytes>"
        print("[APIClient] HTTP \(status), body not the contract: \(preview)")
        #endif
    }
}

#if DEBUG
/// Scripted client for previews and tests: returns the given results without networking.
final class FakeAPIClient: APIClient, @unchecked Sendable {
    var healthResult: Result<API.Health, APIError> = .failure(.unreachable)
    var profilesResult: Result<API.DemoProfiles, APIError> = .failure(.unreachable)
    var evaluationResult: Result<API.Evaluation, APIError> = .failure(.unreachable)
    var planStylesResult: Result<API.PlanStyles, APIError> = .failure(.unreachable)
    private(set) var evaluateRequests: [API.EvaluateRequest] = []

    func health() async throws -> API.Health { try healthResult.get() }
    func demoProfiles() async throws -> API.DemoProfiles { try profilesResult.get() }
    func evaluate(_ request: API.EvaluateRequest) async throws -> API.Evaluation {
        evaluateRequests.append(request)
        return try evaluationResult.get()
    }
    func planStyles(_ profile: API.FinancialProfile) async throws -> API.PlanStyles { try planStylesResult.get() }

    var catalogResult: Result<API.Funds.CatalogSummary, APIError> = .failure(.unreachable)
    var shortlistResult: Result<API.Funds.Envelope, APIError> = .failure(.unreachable)
    var historyStatusResult: Result<API.History.Status, APIError> = .failure(.unreachable)
    var saveRunResult: Result<API.History.SaveRunResponse, APIError> = .failure(.unreachable)
    var runsResult: Result<API.History.RunList, APIError> = .failure(.unreachable)
    var compareResult: Result<API.History.Comparison, APIError> = .failure(.unreachable)

    func fundCatalog() async throws -> API.Funds.CatalogSummary { try catalogResult.get() }
    func fundShortlist(_ query: API.Funds.Query) async throws -> API.Funds.Envelope { try shortlistResult.get() }
    func historyStatus() async throws -> API.History.Status { try historyStatusResult.get() }
    func saveRun(_ request: API.History.SaveRunRequest) async throws -> API.History.SaveRunResponse { try saveRunResult.get() }
    func runs(profileID: String) async throws -> API.History.RunList { try runsResult.get() }
    func compare(base: String, other: String) async throws -> API.History.Comparison { try compareResult.get() }
}
#endif
