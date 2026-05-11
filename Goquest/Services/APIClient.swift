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

    func listTickets(workspaceId: String?, limit: Int = 50, offset: Int = 0) async throws -> TicketListResponse {
        var path = "/tickets?limit=\(limit)&offset=\(offset)"
        if let w = workspaceId, !w.isEmpty {
            path += "&workspace_id=\(w)"
        }
        return try await get(path)
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
