import Foundation

/// Injection seam so StatsViewModel is unit-testable without hitting the
/// network (mirrors the ContractsAPI pattern).
protocol StatsAPI: Sendable {
    func analytics(groupBy: String, workspaceId: String?) async throws -> AnalyticsResponse
    func workspaces() async throws -> [Workspace]
}

extension APIClient: StatsAPI {
    func analytics(groupBy: String, workspaceId: String?) async throws -> AnalyticsResponse {
        try await ticketAnalytics(groupBy: groupBy, workspaceId: workspaceId)
    }
    func workspaces() async throws -> [Workspace] { try await listWorkspaces() }
}

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var workspaces: [Workspace] = []
    /// nil = All workspaces (no workspace_id filter).
    @Published var selectedWorkspace: Workspace?
    @Published var status: [AggBucket] = []
    @Published var priority: [AggBucket] = []
    @Published var type: [AggBucket] = []
    @Published var isLoading = false
    @Published var error: String?

    private let api: StatsAPI
    private static let terminalStatuses: Set<String> = ["completed", "cancelled", "failed"]

    init(api: StatsAPI = APIClient.shared) {
        self.api = api
    }

    /// Open tickets = status buckets minus terminal states.
    var openCount: Int {
        status.filter { !Self.terminalStatuses.contains($0.key) }
              .reduce(0) { $0 + $1.count }
    }

    func loadWorkspaces() async {
        do {
            workspaces = try await api.workspaces()
            if selectedWorkspace == nil, let first = workspaces.first {
                selectedWorkspace = first
            }
        } catch {
            // Non-fatal — picker stays on "All workspaces".
        }
        await load()
    }

    func selectWorkspace(_ ws: Workspace?) async {
        selectedWorkspace = ws
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let wid = selectedWorkspace?.id
        do {
            async let s = api.analytics(groupBy: "status", workspaceId: wid)
            async let p = api.analytics(groupBy: "priority", workspaceId: wid)
            async let t = api.analytics(groupBy: "type", workspaceId: wid)
            let (sr, pr, tr) = try await (s, p, t)
            status = sr.buckets
            priority = pr.buckets
            type = tr.buckets
        } catch {
            self.error = error.localizedDescription
        }
    }
}
