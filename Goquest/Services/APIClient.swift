import Foundation
import OSLog

private let log = Logger(subsystem: "home.toji.goquest", category: "API")

/// Minimal REST client targeting `goquest-service`. All requests carry the
/// caller's ZITADEL access token from `AuthService`.
actor APIClient {
    static let shared = APIClient()

    // NOTE: keep absoluteString-based concatenation rather than URL(string:relativeTo:).
    // `URL(string: "/x", relativeTo: …/api/v1)` resolves the leading slash against
    // the host root, dropping `/api/v1`. We use string concatenation in
    // `authedRequest` to avoid this footgun.
    private let baseURL = "https://goquest.toji.homes/api/v1"
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: cfg)

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601withFractionalSeconds
        self.decoder = d
    }

    // MARK: - Endpoints

    func listWorkspaces() async throws -> [Workspace] {
        let r: WorkspaceListResponse = try await get("/workspaces")
        return r.workspaces
    }

    func listProjects(workspaceId: String) async throws -> [Project] {
        let r: ProjectListResponse = try await get("/workspaces/\(workspaceId)/projects")
        return r.projects
    }

    func listTickets(
        workspaceId: String? = nil,
        projectId: String? = nil,
        q: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> TicketListResponse {
        try await get(APIPath.tickets(workspaceId: workspaceId, projectId: projectId,
                                      q: q, limit: limit, offset: offset))
    }

    /// GET /analytics/tickets — COUNT(*) grouped by one whitelisted column
    /// (status/type/priority/domain/risk_tier/assignee_id/assignee_type).
    func ticketAnalytics(groupBy: String, workspaceId: String? = nil) async throws -> AnalyticsResponse {
        try await get(APIPath.ticketAnalytics(groupBy: groupBy, workspaceId: workspaceId))
    }

    func getTicket(id: String) async throws -> Ticket {
        try await get("/tickets/\(id)")
    }

    func listComments(ticketId: String) async throws -> [Comment] {
        let r: CommentListResponse = try await get("/tickets/\(ticketId)/comments")
        return r.comments
    }

    // MARK: - Device push token

    struct DeviceRegisterPayload: Codable {
        let platform: String
        let apnsToken: String
        let appVersion: String?

        enum CodingKeys: String, CodingKey {
            case platform
            case apnsToken = "apns_token"
            case appVersion = "app_version"
        }
    }

    @discardableResult
    func registerDevice(apnsToken: String, appVersion: String) async throws -> Data {
        let body = DeviceRegisterPayload(platform: "ios", apnsToken: apnsToken, appVersion: appVersion)
        return try await postRaw("/devices/register", body: body)
    }

    // MARK: - Ticket actions

    /// Used by the notification action handler (and the Watch bridge) to flip
    /// a ticket into a terminal state with a single PATCH. Service-side
    /// rejects invalid transitions, so a stale notification can't corrupt.
    @discardableResult
    func patchTicketStatus(id: String, status: String) async throws -> Data {
        struct Body: Encodable { let status: String }
        var req = try await authedRequest(method: "PATCH", path: "/tickets/\(id)")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(status: status))
        let (data, resp) = try await session.data(for: req)
        try Self.throwIfHTTPError(resp, data: data)
        return data
    }

    // MARK: - Internals

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let req = try await authedRequest(method: "GET", path: path)
        log.info("GET \(req.url?.absoluteString ?? "?", privacy: .public)")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
        log.info("  → \(status, privacy: .public) bytes=\(data.count, privacy: .public) preview=\(preview, privacy: .public)")
        try Self.throwIfHTTPError(resp, data: data)
        do {
            return try decoder.decode(T.self, from: data)
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
        let token = try await AuthService.shared.accessToken()
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

/// Pure path builders, kept outside the actor so unit tests can exercise
/// query composition (percent-encoding, filter combinations) directly.
enum APIPath {
    /// Characters allowed inside one query *value*: `.urlQueryAllowed` minus
    /// the separators (&, =, +, ?) so user text can't split parameters.
    private static let queryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&=+?")
        return cs
    }()

    static func tickets(workspaceId: String?, projectId: String?, q: String?,
                        limit: Int, offset: Int) -> String {
        var path = "/tickets?limit=\(limit)&offset=\(offset)"
        if let w = workspaceId, !w.isEmpty { path += "&workspace_id=\(w)" }
        if let p = projectId, !p.isEmpty { path += "&project_id=\(p)" }
        if let query = q?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty,
           let enc = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) {
            path += "&q=\(enc)"
        }
        return path
    }

    static func ticketAnalytics(groupBy: String, workspaceId: String?) -> String {
        var path = "/analytics/tickets?group_by=\(groupBy)"
        if let w = workspaceId, !w.isEmpty { path += "&workspace_id=\(w)" }
        return path
    }
}

enum APIError: Error, LocalizedError {
    case invalidPath(String)
    case http(status: Int, body: String)
    case network

    var errorDescription: String? {
        switch self {
        case .invalidPath(let p): return "Invalid path: \(p)"
        case .http(let s, let b): return "HTTP \(s): \(b)"
        case .network: return "Network error"
        }
    }
}

// Foundation's ISO8601 doesn't handle fractional seconds by default; Go's
// time.Time JSON encoding emits them. The closure-capture of `ISO8601DateFormatter`
// is not Sendable, so we build new formatters inside the closure each call.
// (Formatter creation is cheap relative to network round-trips.)
extension JSONDecoder.DateDecodingStrategy {
    static var iso8601withFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        return .custom { decoder in
            let primary = ISO8601DateFormatter()
            primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]

            let c = try decoder.singleValueContainer()
            let str = try c.decode(String.self)
            if let d = primary.date(from: str) ?? fallback.date(from: str) {
                return d
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(str)")
        }
    }
}
