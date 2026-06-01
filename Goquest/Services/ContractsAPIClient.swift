import Foundation
import OSLog

private let log = Logger(subsystem: "home.toji.goquest", category: "ContractsAPI")

/// Production implementation of `ContractsAPI`. Talks to goquest's `/api/v1`
/// proxy, which forwards to contract-plane. Mirrors `APIClient`'s URLRequest
/// + auth pattern: same base URL, same bearer-token injection via
/// `AuthService`, same iso8601-with-fractional-seconds date decoding.
///
/// `APIClient`'s `get<T>` and `postRaw<B>` helpers are private, so this file
/// reimplements them with matching names/signatures rather than calling
/// across the access boundary. `APIClient` is still injected for parity with
/// the rest of the service layer (and so future helpers added to APIClient
/// can be reused here without changing the public init).
final class ContractsAPIClient: ContractsAPI {
    private let apiClient: APIClient
    private let authService: AuthService
    private let session: URLSession
    private let baseURL = "https://goquest.toji.homes/api/v1"

    init(apiClient: APIClient = .shared, authService: AuthService = .shared) {
        self.apiClient = apiClient
        self.authService = authService
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: cfg)
    }

    // The approver claim that ContractsAPI callers (typically a detail
    // ViewModel) should pass into `approveContract`. ZITADEL ships `email`
    // whenever the `email` scope is requested; `sub` is the always-present
    // fallback. The literal `"unknown"` is a last-resort marker — the
    // backend rejects unauthorized approvers, so it surfaces as a 403 rather
    // than silently approving.
    var resolvedApprover: String {
        get async {
            await MainActor.run {
                (authService.userInfo["email"] as? String)
                    ?? (authService.userInfo["sub"] as? String)
                    ?? "unknown"
            }
        }
    }

    // MARK: - ContractsAPI

    func listContracts(queue: String?, limit: Int) async throws -> [ContractSummary] {
        var path = "/contracts?limit=\(limit)"
        if let q = queue, !q.isEmpty { path += "&queue=\(q)" }
        let resp: ContractListResponse = try await get(path)
        return resp.items
    }

    func getContract(id: String) async throws -> ContractDetail {
        try await get("/contracts/\(id)")
    }

    func approveContract(id: String, approver: String) async throws {
        struct Body: Encodable { let approver: String }
        _ = try await postRaw("/contracts/\(id)/approve", body: Body(approver: approver))
    }

    func abortContract(id: String) async throws {
        struct Body: Encodable {}
        _ = try await postRaw("/contracts/\(id)/abort", body: Body())
    }

    // MARK: - Internals (mirror APIClient.get<T> / postRaw<B> signatures)

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let req = try await authedRequest(method: "GET", path: path)
        log.info("GET \(req.url?.absoluteString ?? "?", privacy: .public)")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        log.info("  → \(status, privacy: .public) bytes=\(data.count, privacy: .public)")
        try Self.throwIfHTTPError(resp, data: data)
        do {
            return try ContractSummary.decoder.decode(T.self, from: data)
        } catch {
            log.error("decode failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func postRaw<B: Encodable>(_ path: String, body: B) async throws -> Data {
        var req = try await authedRequest(method: "POST", path: path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        try Self.throwIfHTTPError(resp, data: data)
        return data
    }

    private func authedRequest(method: String, path: String) async throws -> URLRequest {
        let leadingSlash = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: baseURL + leadingSlash) else {
            throw APIError.invalidPath(path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        let token = try await authService.accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private static func throwIfHTTPError(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw APIError.network }
        if (200...299).contains(http.statusCode) { return }
        let bodyPreview = String(data: data, encoding: .utf8) ?? "<binary>"
        throw APIError.http(status: http.statusCode, body: bodyPreview.prefix(400).description)
    }
}
