import Foundation

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

protocol APIClient: Sendable {
    func health() async throws -> API.Health
    func demoProfiles() async throws -> API.DemoProfiles
    func evaluate(_ request: API.EvaluateRequest) async throws -> API.Evaluation
}

/// URLSession client for the FastAPI backend. Never logs request bodies or tokens.
final class LiveAPIClient: APIClient {
    static let evaluationTimeout: TimeInterval = 8
    static let requestTimeout: TimeInterval = 5

    let baseURL: URL
    private let session: URLSession

    /// Returns nil unless `baseURLString` is an absolute HTTPS URL with a host.
    init?(baseURLString: String, session: URLSession = .shared) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        self.baseURL = url
        self.session = session
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

    private func send<Response: Decodable>(
        path: String, method: String, body: Data?, timeout: TimeInterval
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // ngrok's free tier can interpose a browser warning page; this header opts out.
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
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
    private(set) var evaluateRequests: [API.EvaluateRequest] = []

    func health() async throws -> API.Health { try healthResult.get() }
    func demoProfiles() async throws -> API.DemoProfiles { try profilesResult.get() }
    func evaluate(_ request: API.EvaluateRequest) async throws -> API.Evaluation {
        evaluateRequests.append(request)
        return try evaluationResult.get()
    }
}
#endif
