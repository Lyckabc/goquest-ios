import XCTest
@testable import Goquest

// MARK: - Mock

final class MockStatsAPI: StatsAPI, @unchecked Sendable {
    var analyticsResults: [String: Result<AnalyticsResponse, Error>] = [:]
    var workspacesResult: Result<[Workspace], Error> = .success([])

    private let lock = NSLock()
    private var _requestedGroupBys: [String] = []
    private var _lastWorkspaceArg: String??

    var requestedGroupBys: [String] {
        lock.withLock { _requestedGroupBys }
    }

    var lastWorkspaceArg: String?? {
        lock.withLock { _lastWorkspaceArg }
    }

    func analytics(groupBy: String, workspaceId: String?) async throws -> AnalyticsResponse {
        lock.lock()
        defer { lock.unlock() }
        _requestedGroupBys.append(groupBy)
        _lastWorkspaceArg = workspaceId
        guard let r = analyticsResults[groupBy] else {
            throw APIError.http(status: 500, body: "no stub for \(groupBy)")
        }
        return try r.get()
    }

    func workspaces() async throws -> [Workspace] { try workspacesResult.get() }
}

private func resp(_ groupBy: String, _ pairs: [(String, Int)]) -> AnalyticsResponse {
    AnalyticsResponse(groupBy: groupBy,
                      buckets: pairs.map { AggBucket(key: $0.0, count: $0.1) },
                      total: pairs.reduce(0) { $0 + $1.1 })
}

// MARK: - Tests

@MainActor
final class StatsViewModelTests: XCTestCase {

    func testLoadFetchesThreeGroupBysAndComputesOpenCount() async {
        let api = MockStatsAPI()
        api.analyticsResults["status"] = .success(resp("status", [
            ("pending", 4), ("in_progress", 2), ("completed", 10), ("cancelled", 1), ("failed", 1)]))
        api.analyticsResults["priority"] = .success(resp("priority", [("high", 3), ("normal", 15)]))
        api.analyticsResults["type"] = .success(resp("type", [("task", 12), ("epic", 6)]))
        let vm = StatsViewModel(api: api)
        await vm.load()
        XCTAssertEqual(Set(api.requestedGroupBys), ["status", "priority", "type"])
        XCTAssertEqual(vm.status.count, 5)
        XCTAssertEqual(vm.priority.count, 2)
        XCTAssertEqual(vm.type.count, 2)
        // open = total(18) - completed(10) - cancelled(1) - failed(1)
        XCTAssertEqual(vm.openCount, 6)
        XCTAssertNil(vm.error)
    }

    func testLoadPassesWorkspaceFilter() async {
        let api = MockStatsAPI()
        api.analyticsResults["status"] = .success(resp("status", []))
        api.analyticsResults["priority"] = .success(resp("priority", []))
        api.analyticsResults["type"] = .success(resp("type", []))
        api.workspacesResult = .success([Workspace(id: "w1", name: "Toji", slug: "toji", kind: nil)])
        let vm = StatsViewModel(api: api)
        await vm.loadWorkspaces()
        await vm.selectWorkspace(vm.workspaces.first)
        XCTAssertEqual(vm.selectedWorkspace?.id, "w1")
        XCTAssertEqual(api.lastWorkspaceArg, "w1")
    }

    func testLoadErrorSetsMessage() async {
        let api = MockStatsAPI()
        api.analyticsResults["status"] = .failure(APIError.http(status: 500, body: "boom"))
        api.analyticsResults["priority"] = .success(resp("priority", []))
        api.analyticsResults["type"] = .success(resp("type", []))
        let vm = StatsViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.error)
    }
}
