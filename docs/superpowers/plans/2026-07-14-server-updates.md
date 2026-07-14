# goquest-ios Server-Updates Reflection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** goquest-service의 최근 API 업데이트(풀텍스트 검색, risk_tier/vcs_links 필드, 분석 집계, Lymphhub OIDC)를 iOS 앱에 반영한다.

**Architecture:** 기존 MVVM-lite 패턴(View + `@MainActor ObservableObject` ViewModel + `APIClient` actor)을 그대로 따른다. 신규 Stats 탭은 Contracts 기능의 protocol-주입 패턴(`ContractsAPI` protocol → mock 테스트)을 미러링한다. 모델은 서버 JSON을 snake_case CodingKeys로 그대로 디코드한다.

**Tech Stack:** Swift 5.10 / SwiftUI / Swift Charts (iOS 17, 추가 의존성 없음 — 시스템 프레임워크) / XCTest / XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-14-server-updates-design.md`

## Global Constraints

- Min iOS 17.0, Swift 5.10 (project.yml 기준 — 변경 금지).
- 신규 서드파티 의존성 추가 금지. Swift Charts는 시스템 프레임워크(`import Charts`)라 OK.
- **이 워크스페이스(linux pod)에는 Xcode/Swift 툴체인이 없다.** 테스트 실행 step은 로컬에서 불가 — 테스트 코드를 먼저 작성(TDD 순서 유지)하고 커밋 후 CI(Woodpecker mac agent)가 빌드·테스트를 검증한다. "Run test" step은 "CI에서 검증됨"으로 대체한다.
- 브랜치: `goq-ios-server-updates` (이미 생성됨). 모든 커밋 메시지 본문에 티켓 title_name(`goq-ios-server-updates` 또는 해당 Task 티켓 name)을 포함한다.
- 커밋 트레일러: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` + `Claude-Session: https://claude.ai/code/session_016dzDohBXvwjAiRobSkymEk`
- 서버 값 상수 (goquest `internal/vcs/model.go` 기준): VcsLink `kind` ∈ `branch|commit|pull_request`, `state` ∈ `open|merged|closed|deleted`.
- analytics `group_by` 화이트리스트: `status|type|priority|domain|risk_tier|assignee_id|assignee_type`.

---

### Task 1: 모델 — Ticket 신규 필드 + VcsLink + Analytics

**Files:**
- Modify: `Goquest/Models/Ticket.swift`
- Create: `Goquest/Models/VcsLink.swift`
- Create: `Goquest/Models/Analytics.swift`
- Modify: `GoquestUnitTests/TicketTests.swift` (sample init 갱신 + 디코드 테스트 추가)
- Create: `GoquestUnitTests/ModelDecodingTests.swift`

**Interfaces:**
- Consumes: 없음 (기반 태스크)
- Produces:
  - `Ticket.riskTier: String?`, `Ticket.titleName: String?`, `Ticket.vcsLinks: [VcsLink]?`
  - `struct VcsLink: Codable, Identifiable, Hashable { id, provider, repoFullName, kind, externalRef, url, state, title, sourceBranch, targetBranch: String?/String }`
  - `struct AggBucket: Codable, Hashable { key: String; count: Int }`
  - `struct AnalyticsResponse: Codable { groupBy: String; buckets: [AggBucket]; total: Int }`

- [ ] **Step 1: 실패하는 디코드 테스트 작성** — `GoquestUnitTests/ModelDecodingTests.swift` 생성:

```swift
import XCTest
@testable import Goquest

final class ModelDecodingTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601withFractionalSeconds
        return d
    }

    // 리스트 응답: risk_tier/title_name/vcs_links 전부 없어도 디코드된다.
    func testTicketDecodesWithoutNewFields() throws {
        let json = """
        {"id":"t1","title":"Old","type":"task","status":"pending","priority":"normal",
         "requester_id":"u1","created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-01T00:00:00Z"}
        """.data(using: .utf8)!
        let t = try decoder().decode(Ticket.self, from: json)
        XCTAssertNil(t.riskTier)
        XCTAssertNil(t.titleName)
        XCTAssertNil(t.vcsLinks)
    }

    // 상세 응답: 신규 필드 + vcs_links embed 디코드.
    func testTicketDecodesWithNewFieldsAndVcsLinks() throws {
        let json = """
        {"id":"t1","title":"New","type":"task","status":"in_progress","priority":"high",
         "requester_id":"u1","risk_tier":"high","title_name":"goq-sample-ticket",
         "created_at":"2026-07-01T00:00:00.123Z","updated_at":"2026-07-01T00:00:00.123Z",
         "vcs_links":[{"id":"l1","ticket_id":"t1","provider":"github",
           "repo_full_name":"tojiuni/goquest","kind":"pull_request","external_ref":"73",
           "url":"https://github.com/tojiuni/goquest/pull/73","state":"merged",
           "title":"feat: analytics","source_branch":"goq-analytics-api","target_branch":"main",
           "actor":"neunexus[bot]","created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-01T00:00:00Z"}]}
        """.data(using: .utf8)!
        let t = try decoder().decode(Ticket.self, from: json)
        XCTAssertEqual(t.riskTier, "high")
        XCTAssertEqual(t.titleName, "goq-sample-ticket")
        XCTAssertEqual(t.vcsLinks?.count, 1)
        let link = try XCTUnwrap(t.vcsLinks?.first)
        XCTAssertEqual(link.kind, "pull_request")
        XCTAssertEqual(link.repoFullName, "tojiuni/goquest")
        XCTAssertEqual(link.state, "merged")
        XCTAssertEqual(link.sourceBranch, "goq-analytics-api")
    }

    func testAnalyticsResponseDecodes() throws {
        let json = """
        {"group_by":"status","total":7,"buckets":[
          {"key":"pending","count":4},{"key":"in_progress","count":2},{"key":"","count":1}]}
        """.data(using: .utf8)!
        let r = try decoder().decode(AnalyticsResponse.self, from: json)
        XCTAssertEqual(r.groupBy, "status")
        XCTAssertEqual(r.total, 7)
        XCTAssertEqual(r.buckets.count, 3)
        XCTAssertEqual(r.buckets[0].key, "pending")
        XCTAssertEqual(r.buckets[0].count, 4)
        XCTAssertEqual(r.buckets[2].key, "")
    }
}
```

- [ ] **Step 2: `Goquest/Models/VcsLink.swift` 생성**

```swift
import Foundation

/// One VCS artifact (branch / commit / pull_request) linked to a ticket.
/// Mirrors goquest `internal/vcs/model.go` VcsLink JSON.
struct VcsLink: Codable, Identifiable, Hashable {
    let id: String
    let ticketId: String
    let provider: String
    let repoFullName: String
    /// "branch" | "commit" | "pull_request"
    let kind: String
    let externalRef: String
    let url: String
    /// "open" | "merged" | "closed" | "deleted"
    let state: String
    let title: String
    let sourceBranch: String?
    let targetBranch: String?
    let actor: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, provider, kind, url, state, title, actor
        case ticketId = "ticket_id"
        case repoFullName = "repo_full_name"
        case externalRef = "external_ref"
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

- [ ] **Step 3: `Goquest/Models/Analytics.swift` 생성**

```swift
import Foundation

/// One row of GET /analytics/tickets: group key + count.
/// An empty key means the grouped column was NULL/empty on the server.
struct AggBucket: Codable, Hashable {
    let key: String
    let count: Int
}

struct AnalyticsResponse: Codable {
    let groupBy: String
    let buckets: [AggBucket]
    let total: Int

    enum CodingKeys: String, CodingKey {
        case groupBy = "group_by"
        case buckets, total
    }
}
```

- [ ] **Step 4: `Goquest/Models/Ticket.swift` 수정** — 필드 3개 + CodingKeys 추가. **`let rewardXp: Int?` 바로 아래**에 삽입 (선언 순서가 memberwise init 파라미터 순서를 결정하므로 Step 5의 sample과 일치해야 함):

```swift
    let riskTier: String?
    let titleName: String?
    /// Embedded only on GET /tickets/{id}; absent (nil) in list responses.
    let vcsLinks: [VcsLink]?
```

CodingKeys에 추가:

```swift
        case riskTier = "risk_tier"
        case titleName = "title_name"
        case vcsLinks = "vcs_links"
```

- [ ] **Step 5: `GoquestUnitTests/TicketTests.swift`의 `sample(...)` memberwise init 갱신** — 새 필드 3개를 nil로 전달 (Ticket은 memberwise init이라 전 필드 필수):

```swift
    private func sample(status: String, dueAt: Date? = nil) -> Ticket {
        Ticket(
            id: "t1", title: "Test", description: nil, type: "task",
            status: status, priority: "normal",
            assigneeType: nil, assigneeId: nil, requesterId: "u1",
            projectId: nil, channel: nil,
            requesterName: nil, requesterEmail: nil,
            dueAt: dueAt, createdAt: Date(), updatedAt: Date(),
            completedAt: nil, rewardXp: nil,
            riskTier: nil, titleName: nil, vcsLinks: nil
        )
    }
```

⚠️ 필드 삽입 위치에 따라 memberwise init 파라미터 순서가 달라진다 — Ticket.swift에 선언한 순서 그대로 맞출 것 (rewardXp 뒤에 riskTier/titleName/vcsLinks를 선언했다면 위와 같음).

- [ ] **Step 6: 커밋**

```bash
git add Goquest/Models GoquestUnitTests
git commit -m "feat(models): risk_tier/title_name/vcs_links on Ticket + Analytics models

goq-ios-server-updates"
```

(CI가 push 후 테스트 검증 — Task 6에서 일괄 push.)

---

### Task 2: APIClient — 검색 q 파라미터 + analytics 엔드포인트

**Files:**
- Modify: `Goquest/Services/APIClient.swift`
- Create: `GoquestUnitTests/APIPathTests.swift`

**Interfaces:**
- Consumes: Task 1의 `AnalyticsResponse`
- Produces:
  - `APIClient.listTickets(workspaceId:projectId:q:limit:offset:) async throws -> TicketListResponse` (q 파라미터 추가, 기본값 nil)
  - `APIClient.ticketAnalytics(groupBy:workspaceId:) async throws -> AnalyticsResponse`
  - `enum APIPath { static func tickets(workspaceId:projectId:q:limit:offset:) -> String; static func ticketAnalytics(groupBy:workspaceId:) -> String }` — actor 밖의 순수 함수라 XCTest로 직접 검증 가능

- [ ] **Step 1: 실패하는 경로 조립 테스트 작성** — `GoquestUnitTests/APIPathTests.swift` 생성:

```swift
import XCTest
@testable import Goquest

final class APIPathTests: XCTestCase {

    func testTicketsPathDefault() {
        XCTAssertEqual(APIPath.tickets(workspaceId: nil, projectId: nil, q: nil, limit: 50, offset: 0),
                       "/tickets?limit=50&offset=0")
    }

    func testTicketsPathAllFilters() {
        XCTAssertEqual(
            APIPath.tickets(workspaceId: "w1", projectId: "p1", q: nil, limit: 100, offset: 0),
            "/tickets?limit=100&offset=0&workspace_id=w1&project_id=p1")
    }

    // q는 percent-encode된다: 공백, &, 한글.
    func testTicketsPathEncodesQuery() {
        let path = APIPath.tickets(workspaceId: nil, projectId: nil, q: "빌드 fix&deploy", limit: 50, offset: 0)
        XCTAssertEqual(path, "/tickets?limit=50&offset=0&q=%EB%B9%8C%EB%93%9C%20fix%26deploy")
    }

    // 빈/공백-만 q는 생략된다.
    func testTicketsPathOmitsBlankQuery() {
        XCTAssertEqual(APIPath.tickets(workspaceId: nil, projectId: nil, q: "  ", limit: 50, offset: 0),
                       "/tickets?limit=50&offset=0")
    }

    func testAnalyticsPath() {
        XCTAssertEqual(APIPath.ticketAnalytics(groupBy: "status", workspaceId: "w1"),
                       "/analytics/tickets?group_by=status&workspace_id=w1")
        XCTAssertEqual(APIPath.ticketAnalytics(groupBy: "priority", workspaceId: nil),
                       "/analytics/tickets?group_by=priority")
    }
}
```

- [ ] **Step 2: `APIPath` 구현** — `APIClient.swift` 파일 하단(APIError enum 위)에 추가:

```swift
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
```

주의: 공백은 `%20`으로 인코딩된다(테스트 기대값과 일치). `.urlQueryAllowed`는 공백을 제거한다.

- [ ] **Step 3: `listTickets`를 APIPath 사용 + q 파라미터로 교체, `ticketAnalytics` 추가** — 기존 `listTickets` 본문을 교체:

```swift
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
```

- [ ] **Step 4: 커밋**

```bash
git add Goquest/Services/APIClient.swift GoquestUnitTests/APIPathTests.swift
git commit -m "feat(api): full-text search q param + GET /analytics/tickets client

goq-ios-server-updates"
```

---

### Task 3: 인박스 검색 UI

**Files:**
- Modify: `Goquest/Features/Inbox/InboxView.swift`

**Interfaces:**
- Consumes: Task 2의 `APIClient.listTickets(..., q:)`
- Produces: 없음 (UI 종단)

- [ ] **Step 1: `InboxViewModel`에 검색 상태 + 디바운스 추가** — `@Published var queue` 아래에 추가:

```swift
    @Published var searchText: String = ""
    private var searchTask: Task<Void, Never>?

    /// Debounce 300ms then reload from the server (q param). Called from
    /// .searchable's onChange; empty text reloads the unfiltered list.
    func searchTextChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.loadTickets()
        }
    }
```

- [ ] **Step 2: `loadTickets()`가 q를 전달하도록 수정** — `listTickets` 호출을 교체:

```swift
            let resp = try await APIClient.shared.listTickets(
                workspaceId: selectedWorkspace?.id,
                projectId: selectedProject?.id,
                q: searchText,
                limit: 100
            )
```

(빈 문자열은 APIPath가 알아서 생략하므로 분기 불필요.)

- [ ] **Step 3: `InboxView`에 `.searchable` 부착** — `.navigationTitle("Inbox")` 바로 아래에 추가:

```swift
        .searchable(text: $vm.searchText, prompt: "Search tickets")
        .onChange(of: vm.searchText) { vm.searchTextChanged() }
```

검색 결과 빈 상태 문구도 구분: 기존 `ContentUnavailableView("No tickets", ...)`를 다음으로 교체:

```swift
                if vm.searchText.isEmpty {
                    ContentUnavailableView("No tickets", systemImage: "tray",
                        description: Text("\(vm.queue.rawValue) queue is empty."))
                } else {
                    ContentUnavailableView.search(text: vm.searchText)
                }
```

- [ ] **Step 4: 커밋**

```bash
git add Goquest/Features/Inbox/InboxView.swift
git commit -m "feat(inbox): server-side full-text search via .searchable + debounce

goq-ios-server-updates"
```

---

### Task 4: RiskTierBadge + Development(VCS 링크) 섹션

**Files:**
- Modify: `Goquest/UI/Badges.swift` (RiskTierBadge 추가)
- Modify: `Goquest/Features/Inbox/InboxView.swift` (`TicketRow`에 배지)
- Modify: `Goquest/Features/TicketDetail/TicketDetailView.swift` (Meta에 risk, Development 섹션 + `VcsLinkRow`)

**Interfaces:**
- Consumes: Task 1의 `Ticket.riskTier`, `Ticket.vcsLinks`, `VcsLink`
- Produces: `RiskTierBadge(tier: String)`, `VcsLinkRow(link: VcsLink)` 뷰

- [ ] **Step 1: `RiskTierBadge` 추가** — `Badges.swift` 하단에 PriorityBadge 패턴으로:

```swift
struct RiskTierBadge: View {
    let tier: String
    var color: Color {
        switch tier {
        case "critical": return .red
        case "high":     return .orange
        case "medium":   return .blue
        case "low":      return .gray
        default:         return .secondary   // unknown tier from a newer server
        }
    }
    var body: some View {
        Label(tier.uppercased(), systemImage: "shield.lefthalf.filled")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}
```

- [ ] **Step 2: `TicketRow`에 배지 표시** — `InboxView.swift`의 TicketRow 두 번째 HStack에서 `StatusBadge(status:)` 바로 뒤에 추가:

```swift
                if let tier = ticket.riskTier, !tier.isEmpty {
                    RiskTierBadge(tier: tier)
                }
```

- [ ] **Step 3: `TicketDetailView` Meta 섹션에 Risk 행 추가** — `LabeledContent("Priority")` 아래에:

```swift
                    if let tier = t.riskTier, !tier.isEmpty {
                        LabeledContent("Risk") { RiskTierBadge(tier: tier) }
                    }
```

- [ ] **Step 4: Development 섹션 + `VcsLinkRow` 추가** — `TicketDetailView.swift`에서 Description 섹션 뒤(Conversation 섹션 앞)에:

```swift
                if let links = t.vcsLinks, !links.isEmpty {
                    Section("Development") {
                        ForEach(links) { link in
                            VcsLinkRow(link: link)
                        }
                    }
                }
```

파일 하단(CommentRow 아래)에 행 뷰:

```swift
struct VcsLinkRow: View {
    let link: VcsLink

    private var icon: String {
        switch link.kind {
        case "branch":       return "arrow.triangle.branch"
        case "pull_request": return "arrow.triangle.merge"
        case "commit":       return "number"
        default:             return "link"
        }
    }

    private var stateColor: Color {
        switch link.state {
        case "merged": return .purple
        case "open":   return .green
        default:       return .gray   // closed / deleted
        }
    }

    /// PR title when present, else the ref (branch name / short SHA / PR number).
    private var primaryText: String {
        link.title.isEmpty ? link.externalRef : link.title
    }

    var body: some View {
        if let url = URL(string: link.url) {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText).font(.callout).lineLimit(1).foregroundStyle(.primary)
                Text(link.repoFullName).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if link.kind == "pull_request" {
                Text(link.state)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(stateColor.opacity(0.15))
                    .foregroundStyle(stateColor)
                    .cornerRadius(4)
            }
        }
    }
}
```

- [ ] **Step 5: 커밋**

```bash
git add Goquest/UI/Badges.swift Goquest/Features/Inbox/InboxView.swift Goquest/Features/TicketDetail/TicketDetailView.swift
git commit -m "feat(ui): risk_tier badge + Development section with VCS links

goq-ios-server-updates"
```

---

### Task 5: Stats 탭 (Swift Charts)

**Files:**
- Create: `Goquest/Features/Stats/StatsViewModel.swift`
- Create: `Goquest/Features/Stats/StatsView.swift`
- Modify: `Goquest/Features/Inbox/MainTabView.swift`
- Create: `GoquestUnitTests/StatsViewModelTests.swift`

**Interfaces:**
- Consumes: Task 1 `AnalyticsResponse`/`AggBucket`, Task 2 `APIClient.ticketAnalytics(groupBy:workspaceId:)`, 기존 `APIClient.listWorkspaces()`
- Produces:
  - `protocol StatsAPI: Sendable { func analytics(groupBy: String, workspaceId: String?) async throws -> AnalyticsResponse; func workspaces() async throws -> [Workspace] }`
  - `APIClient: StatsAPI` conformance (extension)
  - `StatsViewModel(api: StatsAPI)` — `@Published var status/priority/type: [AggBucket]`, `openCount: Int`, `load()`, `selectWorkspace(_:)`

- [ ] **Step 1: 실패하는 ViewModel 테스트 작성** — `GoquestUnitTests/StatsViewModelTests.swift` 생성 (Contracts의 mock 패턴 미러):

```swift
import XCTest
@testable import Goquest

// MARK: - Mock

final class MockStatsAPI: StatsAPI, @unchecked Sendable {
    var analyticsResults: [String: Result<AnalyticsResponse, Error>] = [:]
    var workspacesResult: Result<[Workspace], Error> = .success([])
    private(set) var requestedGroupBys: [String] = []
    private(set) var lastWorkspaceArg: String??

    func analytics(groupBy: String, workspaceId: String?) async throws -> AnalyticsResponse {
        requestedGroupBys.append(groupBy)
        lastWorkspaceArg = workspaceId
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
```

- [ ] **Step 2: `StatsViewModel.swift` 구현**

```swift
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
```

- [ ] **Step 3: `StatsView.swift` 구현** — Swift Charts 가로 바 3개 + open 카드:

```swift
import SwiftUI
import Charts

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()

    private static let allWorkspacesTag = "__all__"

    var body: some View {
        List {
            if !vm.workspaces.isEmpty {
                Section {
                    Picker("Workspace", selection: Binding(
                        get: { vm.selectedWorkspace?.id ?? Self.allWorkspacesTag },
                        set: { newId in
                            let target = newId == Self.allWorkspacesTag
                                ? nil
                                : vm.workspaces.first { $0.id == newId }
                            Task { await vm.selectWorkspace(target) }
                        }
                    )) {
                        Text("All workspaces").tag(Self.allWorkspacesTag)
                        ForEach(vm.workspaces) { w in
                            Text(w.name).tag(w.id)
                        }
                    }
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open tickets").font(.caption).foregroundStyle(.secondary)
                        Text("\(vm.openCount)").font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Image(systemName: "tray.full").font(.title).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if vm.isLoading && vm.status.isEmpty {
                ProgressView()
            } else {
                bucketChart(title: "By status", buckets: vm.status)
                bucketChart(title: "By priority", buckets: vm.priority)
                bucketChart(title: "By type", buckets: vm.type)
            }
        }
        .navigationTitle("Stats")
        .refreshable { await vm.load() }
        .task { await vm.loadWorkspaces() }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { _ in vm.error = nil })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    @ViewBuilder
    private func bucketChart(title: String, buckets: [AggBucket]) -> some View {
        Section(title) {
            if buckets.isEmpty {
                Text("No data").foregroundStyle(.secondary).font(.caption)
            } else {
                Chart(buckets, id: \.key) { b in
                    BarMark(
                        x: .value("Count", b.count),
                        y: .value("Key", displayKey(b.key))
                    )
                    .annotation(position: .trailing) {
                        Text("\(b.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                // 행당 28pt — 버킷 수에 따라 늘어나는 가로 바 차트.
                .frame(height: max(CGFloat(buckets.count) * 28, 44))
                .padding(.vertical, 4)
            }
        }
    }

    /// Server sends "" for NULL/empty group values; underscores read badly.
    private func displayKey(_ key: String) -> String {
        key.isEmpty ? "none" : key.replacingOccurrences(of: "_", with: " ")
    }
}
```

- [ ] **Step 4: `MainTabView.swift`에 탭 추가** — Inbox 다음에:

```swift
            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
```

- [ ] **Step 5: 커밋**

```bash
git add Goquest/Features/Stats GoquestUnitTests/StatsViewModelTests.swift Goquest/Features/Inbox/MainTabView.swift
git commit -m "feat(stats): analytics tab — status/priority/type charts + open count

goq-ios-server-updates"
```

---

### Task 6: Lymphhub 인증 전환 + 문서/CI 반영

**Files:**
- Modify: `Goquest/Services/AuthService.swift`
- Modify: `README.md` (ZITADEL 섹션 → Lymphhub)
- Modify: `docs/TODO.md` (Bundle hygiene의 clientID xcconfig 항목 처리 표기)

**Interfaces:**
- Consumes: 없음
- Produces: 없음 (설정 변경)

**선행 조건:** Lymphhub native PKCE 앱 등록(별도 인프라 티켓). 등록 전까지 clientID는 Info.plist 주입값이 없으면 기존 ZITADEL id로 폴백 — 서버가 dual-JWKS라 앱은 계속 동작한다.

- [ ] **Step 1: `AuthService.swift` — issuer/clientID/redirect 교체**. 기존 25~30행의 설정 블록을 다음으로 교체:

```swift
    // Lymphhub OIDC (standard discovery, EdDSA JWTs). goquest-service trusts
    // both Lymphhub and legacy ZITADEL via dual-JWKS during the migration, so
    // existing ZITADEL sessions keep working until their refresh fails.
    // client_id comes from Info.plist (GoquestOIDCClientID, xcconfig-injectable);
    // the hardcoded fallback is the legacy ZITADEL client so a build without
    // the new id still logs in (via the old issuer) during the transition.
    private let issuer: URL
    private let clientID: String
    private let redirectURI: URL

    private init() {
        if let injected = Bundle.main.object(forInfoDictionaryKey: "GoquestOIDCClientID") as? String,
           !injected.isEmpty, !injected.hasPrefix("$(") {
            issuer = URL(string: "https://toji.idp.toji.homes")!
            clientID = injected
            redirectURI = URL(string: "home.toji.goquest://oauth2redirect/lymphhub")!
        } else {
            // Legacy ZITADEL fallback — remove once the Lymphhub app is
            // registered and GOQUEST_OIDC_CLIENT_ID is set in xcconfig.
            issuer = URL(string: "https://auth.toji.homes")!
            clientID = "372400414877936855"
            redirectURI = URL(string: "home.toji.goquest://oauth2redirect/zitadel")!
        }
    }
```

주의: `AuthService`는 `static let shared = AuthService()` 싱글턴 — 기존에 암시적 init이었다면 `private init()` 추가로 동작 동일. discovery failed 에러 문구도 갱신: `case .discoveryFailed: return "OIDC discovery failed"`.

- [ ] **Step 2: `project.yml`에 Info.plist 키 추가** — Goquest 타깃 `info.properties`에:

```yaml
        # Lymphhub OIDC client id — inject via xcconfig (GOQUEST_OIDC_CLIENT_ID).
        # Empty/unset ⇒ AuthService falls back to the legacy ZITADEL client.
        GoquestOIDCClientID: $(GOQUEST_OIDC_CLIENT_ID)
```

- [ ] **Step 3: README.md의 "ZITADEL OIDC app" 섹션을 Lymphhub로 갱신** — 표의 Auth 행을 `Lymphhub OIDC PKCE (legacy ZITADEL fallback) via AppAuth-iOS`로, 섹션 본문을 다음 요지로 교체: Lymphhub(`https://toji.idp.toji.homes`)에 native PKCE 앱 등록(redirect `home.toji.goquest://oauth2redirect/lymphhub`, grant authorization_code+refresh_token, no secret), client_id는 `GOQUEST_OIDC_CLIENT_ID` xcconfig로 주입, Vault `secret/neunexus/sso/goquest-ios` 참조.

- [ ] **Step 4: docs/TODO.md 갱신** — Bundle hygiene의 "Move clientID to an .xcconfig file" 항목을 `[x]`로 바꾸고 `(GoquestOIDCClientID Info.plist key — 2026-07-14)` 주석 추가.

- [ ] **Step 5: 커밋 + push (CI 검증)**

```bash
git add Goquest/Services/AuthService.swift project.yml README.md docs/TODO.md
git commit -m "feat(auth): Lymphhub OIDC switch with xcconfig client_id + ZITADEL fallback

goq-ios-server-updates"
git push -u origin goq-ios-server-updates
```

Push 후 Woodpecker CI(mac agent)가 xcodegen + 빌드 + GoquestUnitTests를 실행한다. CI green 확인이 이 플랜의 최종 검증이다. 실패 시 로그를 읽고 해당 Task로 돌아가 수정한다.

---

## 최종 체크리스트

- [ ] CI green (빌드 + 전체 유닛 테스트)
- [ ] 인프라 후속 티켓 생성: Lymphhub native 앱 등록 (`neunexus/services/lymphhub/sso-apps.tf`, redirect `home.toji.goquest://oauth2redirect/lymphhub`) → client_id를 Vault `secret/neunexus/sso/goquest-ios`에 기록
- [ ] PR 생성 (제목에 `goq-ios-server-updates` 포함 — goquest VCS 자동 링크)
- [ ] geneso 문서 반영 검토 (`goquest/service/ios/` — 인증 전환·새 화면 요약)
