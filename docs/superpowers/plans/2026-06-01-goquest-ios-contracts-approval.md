# goquest-ios — contracts approval gate handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Contracts tab to goquest-ios so an operator can list pending approval gates, see goal context, and Approve/Abort from the phone.

**Architecture:** New `Goquest/Features/Contracts/` directory. Models in `Goquest/Models/Contract.swift`. `ContractsAPI` protocol so ViewModels can mock the network in tests. Pull-based — pull-to-refresh refreshes; no SSE / push for this spec.

**Tech Stack:** SwiftUI, async/await, XCTest, AppAuth-iOS (existing OIDC). Backend endpoints already exist on `goquest` (proxy to `contract-plane`): `/api/v1/contracts?queue=…`, `/api/v1/contracts/{id}`, `/api/v1/contracts/{id}/approve`, `/api/v1/contracts/{id}/abort`.

**Working directory:** `/Users/dong-hoshin/Documents/dev/goquest-ios` (or a worktree off `spec/contracts-approval` — see Task 0).

**Spec:** `docs/superpowers/specs/2026-06-01-goquest-ios-contracts-approval-design.md`

---

## Task 0: Working branch

- [ ] **Step 0.1: Create the implementation branch from the spec branch**

```bash
cd /Users/dong-hoshin/Documents/dev/goquest-ios
git fetch origin
git worktree add /tmp/gi-impl feat/ios-contracts-approval spec/contracts-approval
cd /tmp/gi-impl
git log --oneline -3
```

Expected: branch `feat/ios-contracts-approval` exists, pointing at the spec commit `b82d6e2`. All subsequent tasks run from `/tmp/gi-impl`.

---

## Task 1: `Contract` models + decoding tests

**Files:**
- Create: `Goquest/Models/Contract.swift`
- Create: `GoquestUnitTests/ContractTests.swift`

- [ ] **Step 1.1: Write the failing decoding test**

Create `/tmp/gi-impl/GoquestUnitTests/ContractTests.swift`:

```swift
import XCTest
@testable import Goquest

final class ContractTests: XCTestCase {

    func testSummaryDecodes() throws {
        let json = """
        {
          "workflow_id": "contract-abc",
          "contract_id": "ctr_abc",
          "state": "gate_pending",
          "goal": "deploy service",
          "workspace": "ws-prod",
          "origin": {"channel": "slack", "actor": "alice"},
          "risk_tier": "medium",
          "step_count": 4,
          "started_at": "2026-06-01T00:00:00Z",
          "updated_at": "2026-06-01T00:05:00Z"
        }
        """.data(using: .utf8)!
        let s = try ContractSummary.decoder.decode(ContractSummary.self, from: json)
        XCTAssertEqual(s.workflowId, "contract-abc")
        XCTAssertEqual(s.state, "gate_pending")
        XCTAssertEqual(s.goal, "deploy service")
        XCTAssertEqual(s.origin?.channel, "slack")
        XCTAssertEqual(s.origin?.actor, "alice")
        XCTAssertTrue(s.isPendingGate)
    }

    func testDetailDecodesWithPlanAndLedger() throws {
        let json = """
        {
          "workflow_id": "contract-abc",
          "contract_id": "ctr_abc",
          "state": "gate_pending",
          "workspace": "ws-prod",
          "goal": "deploy service",
          "origin": {"channel": "slack", "actor": "alice"},
          "ledger": [
            {"step_id": "s1", "status": "ok",
             "verdict": {"passed": true, "reason": "checks pass"}}
          ],
          "plan": {"steps": [{"step_id": "s1", "capability": "ticket.create"}],
                   "risk_tier": "low", "max_steps": 8}
        }
        """.data(using: .utf8)!
        let d = try ContractSummary.decoder.decode(ContractDetail.self, from: json)
        XCTAssertEqual(d.workflowId, "contract-abc")
        XCTAssertEqual(d.plan?.steps.count, 1)
        XCTAssertEqual(d.ledger.count, 1)
        XCTAssertTrue(d.isPendingGate)
    }

    func testDetailDecodesEmptyPlan() throws {
        let json = """
        {
          "workflow_id": "contract-abc",
          "state": "running",
          "ledger": [],
          "plan": null
        }
        """.data(using: .utf8)!
        let d = try ContractSummary.decoder.decode(ContractDetail.self, from: json)
        XCTAssertNil(d.plan)
        XCTAssertEqual(d.ledger.count, 0)
        XCTAssertFalse(d.isPendingGate)
    }
}
```

- [ ] **Step 1.2: Run the test to verify it fails**

Open `Goquest.xcodeproj` in Xcode, target `GoquestUnitTests`, run `ContractTests`. Expected: build FAILS — `ContractSummary` and `ContractDetail` not defined.

CLI equivalent (run from `/tmp/gi-impl`):

```bash
xcodebuild test -project Goquest.xcodeproj \
  -scheme GoquestUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GoquestUnitTests/ContractTests 2>&1 | tail -20
```

Expected: BUILD FAILED (`ContractSummary` undefined).

- [ ] **Step 1.3: Create `Contract.swift`**

Create `/tmp/gi-impl/Goquest/Models/Contract.swift`:

```swift
import Foundation

// Backend response shape mirrors the web's contractPlaneApi.ts definitions.
// All fields except workflow_id and state are optional so a partial backend
// response (older deployments) still decodes.

struct ContractOrigin: Codable, Hashable {
    let channel: String?
    let actor: String?
}

struct ContractSummary: Codable, Identifiable, Hashable {
    let workflowId: String
    let contractId: String?
    let state: String        // "planning" | "gate_pending" | "running" | "done" | "aborted" | "unknown" (plus Temporal terminal states)
    let goal: String?
    let workspace: String?
    let origin: ContractOrigin?
    let riskTier: String?
    let stepCount: Int?
    let startedAt: Date?
    let updatedAt: Date?
    let summaryTitle: String?
    let firstTicketTitle: String?
    let workspaceName: String?
    let projectName: String?

    var id: String { workflowId }

    var isPendingGate: Bool { state == "gate_pending" }

    enum CodingKeys: String, CodingKey {
        case workflowId = "workflow_id"
        case contractId = "contract_id"
        case state, goal, workspace, origin
        case riskTier = "risk_tier"
        case stepCount = "step_count"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case summaryTitle = "summary_title"
        case firstTicketTitle = "first_ticket_title"
        case workspaceName = "workspace_name"
        case projectName = "project_name"
    }

    // Shared JSONDecoder configured for the backend's ISO-8601-with-fractional-
    // seconds dates, matching what APIClient already uses for tickets.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601withFractionalSeconds
        return d
    }()
}

struct ContractPlanStep: Codable, Identifiable, Hashable {
    let stepId: String
    let capability: String
    let target: String?

    var id: String { stepId }

    enum CodingKeys: String, CodingKey {
        case stepId = "step_id"
        case capability, target
    }
}

struct ContractPlan: Codable, Hashable {
    let steps: [ContractPlanStep]
    let riskTier: String?
    let maxSteps: Int?

    enum CodingKeys: String, CodingKey {
        case steps
        case riskTier = "risk_tier"
        case maxSteps = "max_steps"
    }
}

struct ContractVerdict: Codable, Hashable {
    let passed: Bool
    let reason: String?
}

struct ContractLedgerEntry: Codable, Identifiable, Hashable {
    let stepId: String
    let status: String
    let verdict: ContractVerdict?

    var id: String { stepId }

    enum CodingKeys: String, CodingKey {
        case stepId = "step_id"
        case status, verdict
    }
}

struct ContractDetail: Codable, Identifiable, Hashable {
    let workflowId: String
    let contractId: String?
    let state: String
    let goal: String?
    let workspace: String?
    let origin: ContractOrigin?
    let plan: ContractPlan?
    let ledger: [ContractLedgerEntry]
    let abortReason: String?
    let refIds: [String]?
    let summaryTitle: String?

    var id: String { workflowId }
    var isPendingGate: Bool { state == "gate_pending" }

    enum CodingKeys: String, CodingKey {
        case workflowId = "workflow_id"
        case contractId = "contract_id"
        case state, goal, workspace, origin, plan, ledger
        case abortReason = "abort_reason"
        case refIds = "ref_ids"
        case summaryTitle = "summary_title"
    }
}

// Wire shape for `GET /contracts?queue=…` — the backend returns
// `{"items": [...], "next_page_token": "..."}`.
struct ContractListResponse: Codable {
    let items: [ContractSummary]
    let nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextPageToken = "next_page_token"
    }
}
```

- [ ] **Step 1.4: Run the test to verify it passes**

```bash
xcodebuild test -project Goquest.xcodeproj \
  -scheme GoquestUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GoquestUnitTests/ContractTests 2>&1 | tail -15
```

Expected: 3 of 3 PASS.

- [ ] **Step 1.5: Commit**

```bash
cd /tmp/gi-impl
git add Goquest/Models/Contract.swift GoquestUnitTests/ContractTests.swift
git commit -m "feat(contracts): Codable models — Summary, Detail, Plan, Ledger

Shape mirrors goquest-ui's contractPlaneApi.ts. Most fields optional to
tolerate older backends. Three decoding tests cover summary, detail with
plan+ledger, and a detail with a null plan."
```

---

## Task 2: `ContractsAPI` protocol + `APIClient` extension

**Files:**
- Create: `Goquest/Services/ContractsAPI.swift`
- Modify: `Goquest/Services/APIClient.swift` (extend with 4 methods, conform to protocol)

The protocol is what ViewModels depend on. `APIClient` is the production implementation; tests inject a mock.

- [ ] **Step 2.1: Create the protocol file**

Create `/tmp/gi-impl/Goquest/Services/ContractsAPI.swift`:

```swift
import Foundation

// Protocol surface for the contracts subset of the goquest API. ViewModels
// depend on this so tests can inject a mock without touching URLSession.
// APIClient conforms via an extension below in APIClient.swift.
protocol ContractsAPI {
    func listContracts(queue: String?, limit: Int) async throws -> [ContractSummary]
    func getContract(id: String) async throws -> ContractDetail
    func approveContract(id: String, approver: String) async throws
    func abortContract(id: String) async throws
}
```

- [ ] **Step 2.2: Add the implementation to `APIClient.swift`**

Open `/tmp/gi-impl/Goquest/Services/APIClient.swift`. Find the `getTicket(id:)` method (around line 57-59) and add the four new methods immediately after it. Then add a protocol conformance at the top of the file.

First, near the top of `APIClient.swift` where `final class APIClient {` is declared (around line 7), change the declaration to also conform to `ContractsAPI`:

Find:
```swift
final class APIClient {
```

Replace with:
```swift
final class APIClient: ContractsAPI {
```

Then locate `getTicket(id:)` (the second public method, around line 57) and insert these four methods immediately after its closing brace:

```swift
    // MARK: - Contracts

    func listContracts(queue: String?, limit: Int = 50) async throws -> [ContractSummary] {
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
```

(The existing `get<T>` and `postRaw` generic helpers already handle auth, decode, and error mapping. The `ContractSummary.decoder`'s `iso8601withFractionalSeconds` strategy is identical to the one APIClient already uses, so dates parse correctly without further configuration.)

- [ ] **Step 2.3: Verify the project still builds**

```bash
cd /tmp/gi-impl
xcodebuild build -project Goquest.xcodeproj -scheme Goquest \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2.4: Commit**

```bash
cd /tmp/gi-impl
git add Goquest/Services/ContractsAPI.swift Goquest/Services/APIClient.swift
git commit -m "feat(contracts): ContractsAPI protocol + APIClient methods

list/get/approve/abort against the existing goquest proxy. APIClient
conforms to the protocol so ViewModels can inject mocks in tests."
```

---

## Task 3: `ContractsViewModel` + tests

**Files:**
- Create: `Goquest/Features/Contracts/ContractsViewModel.swift`
- Modify: `GoquestUnitTests/ContractTests.swift` (append VM tests + mock)

- [ ] **Step 3.1: Write the failing tests + mock**

Append to `/tmp/gi-impl/GoquestUnitTests/ContractTests.swift`:

```swift

// MARK: - ContractsViewModel

@MainActor
final class ContractsViewModelTests: XCTestCase {

    func testLoadPopulatesContracts() async {
        let api = MockContractsAPI()
        api.listResult = .success([
            sampleSummary(id: "wf-1", goal: "G1"),
            sampleSummary(id: "wf-2", goal: "G2"),
        ])
        let vm = ContractsViewModel(api: api)
        await vm.load(queue: .pendingGates)
        XCTAssertEqual(vm.contracts.count, 2)
        XCTAssertEqual(vm.contracts.first?.workflowId, "wf-1")
        XCTAssertNil(vm.error)
        XCTAssertEqual(api.lastQueueArg, "awaiting_plan")
    }

    func testLoadEmpty() async {
        let api = MockContractsAPI()
        api.listResult = .success([])
        let vm = ContractsViewModel(api: api)
        await vm.load(queue: .pendingGates)
        XCTAssertTrue(vm.contracts.isEmpty)
        XCTAssertNil(vm.error)
    }

    func testLoadNetworkErrorSetsErrorMessage() async {
        let api = MockContractsAPI()
        api.listResult = .failure(NSError(domain: "net", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "offline"]))
        let vm = ContractsViewModel(api: api)
        await vm.load(queue: .pendingGates)
        XCTAssertTrue(vm.contracts.isEmpty)
        XCTAssertNotNil(vm.error)
    }

    private func sampleSummary(id: String, goal: String) -> ContractSummary {
        ContractSummary(
            workflowId: id, contractId: nil, state: "gate_pending",
            goal: goal, workspace: nil, origin: nil, riskTier: nil,
            stepCount: nil, startedAt: nil, updatedAt: nil,
            summaryTitle: nil, firstTicketTitle: nil,
            workspaceName: nil, projectName: nil
        )
    }
}

// Lightweight in-memory ContractsAPI mock for VM tests.
final class MockContractsAPI: ContractsAPI {
    var listResult: Result<[ContractSummary], Error> = .success([])
    var detailResult: Result<ContractDetail, Error> = .failure(NSError(domain: "test", code: 0))
    var approveResult: Result<Void, Error> = .success(())
    var abortResult: Result<Void, Error> = .success(())

    private(set) var lastQueueArg: String?
    private(set) var lastApproverArg: String?
    private(set) var lastApprovedId: String?
    private(set) var lastAbortedId: String?

    func listContracts(queue: String?, limit: Int) async throws -> [ContractSummary] {
        lastQueueArg = queue
        return try listResult.get()
    }
    func getContract(id: String) async throws -> ContractDetail {
        try detailResult.get()
    }
    func approveContract(id: String, approver: String) async throws {
        lastApprovedId = id
        lastApproverArg = approver
        return try approveResult.get()
    }
    func abortContract(id: String) async throws {
        lastAbortedId = id
        return try abortResult.get()
    }
}
```

- [ ] **Step 3.2: Run the test to verify it fails**

```bash
cd /tmp/gi-impl
xcodebuild test -project Goquest.xcodeproj -scheme GoquestUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GoquestUnitTests/ContractsViewModelTests 2>&1 | tail -10
```

Expected: BUILD FAILED — `ContractsViewModel` undefined.

- [ ] **Step 3.3: Create the ViewModel**

Create `/tmp/gi-impl/Goquest/Features/Contracts/ContractsViewModel.swift`:

```swift
import Foundation

@MainActor
final class ContractsViewModel: ObservableObject {
    enum Queue: String, CaseIterable, Identifiable {
        case pendingGates = "Pending Gates"
        case running = "Running"
        case recent = "Recent"

        var id: String { rawValue }

        // Maps to the contract-plane `?queue=…` query param. `recent` sends no
        // filter so the API returns everything in created-at order.
        var queryParam: String? {
            switch self {
            case .pendingGates: return "awaiting_plan"
            case .running:      return "running"
            case .recent:       return nil
            }
        }
    }

    @Published private(set) var contracts: [ContractSummary] = []
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var selectedQueue: Queue = .pendingGates

    private let api: ContractsAPI

    init(api: ContractsAPI = APIClient.shared) {
        self.api = api
    }

    func load(queue: Queue) async {
        selectedQueue = queue
        isLoading = true
        defer { isLoading = false }
        do {
            contracts = try await api.listContracts(queue: queue.queryParam, limit: 50)
        } catch {
            self.error = error.localizedDescription
            contracts = []
        }
    }
}
```

- [ ] **Step 3.4: Run the test to verify it passes**

```bash
cd /tmp/gi-impl
xcodebuild test -project Goquest.xcodeproj -scheme GoquestUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GoquestUnitTests/ContractsViewModelTests 2>&1 | tail -10
```

Expected: 3 of 3 PASS.

- [ ] **Step 3.5: Commit**

```bash
cd /tmp/gi-impl
git add Goquest/Features/Contracts/ContractsViewModel.swift \
        GoquestUnitTests/ContractTests.swift
git commit -m "feat(contracts): ContractsViewModel + MockContractsAPI for tests

3 VM tests cover happy-path load, empty result, and network error.
Mock asserts queue=awaiting_plan reaches the API."
```

---

## Task 4: `ContractsView` (list UI)

**Files:**
- Create: `Goquest/Features/Contracts/ContractsView.swift`

No unit tests here — the existing app has no SwiftUI snapshot harness. The smoke UI test in Task 7 covers the screen surface-level.

- [ ] **Step 4.1: Create the view**

Create `/tmp/gi-impl/Goquest/Features/Contracts/ContractsView.swift`:

```swift
import SwiftUI

struct ContractsView: View {
    @StateObject private var vm = ContractsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Queue", selection: $vm.selectedQueue) {
                ForEach(ContractsViewModel.Queue.allCases) { q in
                    Text(q.rawValue).tag(q)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            List {
                if vm.isLoading && vm.contracts.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if vm.contracts.isEmpty {
                    Text(emptyMessage(for: vm.selectedQueue))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(vm.contracts) { c in
                        NavigationLink {
                            ContractDetailView(workflowId: c.workflowId)
                        } label: {
                            ContractRow(summary: c)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Contracts")
        .task { await vm.load(queue: vm.selectedQueue) }
        .refreshable { await vm.load(queue: vm.selectedQueue) }
        .onChange(of: vm.selectedQueue) { _, newValue in
            Task { await vm.load(queue: newValue) }
        }
        .alert("Error", isPresented: Binding(get: { vm.error != nil },
                                              set: { _ in vm.error = nil })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }

    private func emptyMessage(for q: ContractsViewModel.Queue) -> String {
        switch q {
        case .pendingGates: return "No pending gates."
        case .running:      return "No active workflows."
        case .recent:       return "No contracts yet."
        }
    }
}

private struct ContractRow: View {
    let summary: ContractSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StateBadge(state: summary.state)
                Text(summary.summaryTitle ?? summary.goal ?? "(no goal)")
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let started = summary.startedAt {
                    Text(started, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let ws = summary.workspaceName ?? summary.workspace, !ws.isEmpty {
                    Text(ws).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StateBadge: View {
    let state: String
    var body: some View {
        Text(state).font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch state {
        case "gate_pending": return .orange
        case "running":      return .blue
        case "done", "completed": return .green
        case "aborted", "failed", "canceled", "terminated": return .red
        default: return .gray
        }
    }
}
```

- [ ] **Step 4.2: Verify the project builds**

```bash
cd /tmp/gi-impl
xcodebuild build -project Goquest.xcodeproj -scheme Goquest \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. (`ContractDetailView` is referenced but is the next task — Xcode resolves it lazily; the build still has an unresolved reference. If the build fails on this missing symbol, comment out the `NavigationLink` for now and uncomment in Task 6. **Preferred: jump to Task 6 first, create the empty `ContractDetailView` shim, then return here for the build check.**)

Practical sequencing: leave the `NavigationLink { ContractDetailView(workflowId: c.workflowId) }` in place — Task 6 will fill it in. Don't commit until Task 6's view compiles. **Commit at the end of Task 6**, not here.

(Skipping the commit step in this task is intentional: the View depends on a symbol defined in Task 6. Build-greenness gates the commit.)

---

## Task 5: `ContractDetailViewModel` + tests

**Files:**
- Create: `Goquest/Features/Contracts/ContractDetailViewModel.swift`
- Modify: `GoquestUnitTests/ContractTests.swift` (append detail VM tests)

- [ ] **Step 5.1: Append failing tests**

Append to `/tmp/gi-impl/GoquestUnitTests/ContractTests.swift`:

```swift

// MARK: - ContractDetailViewModel

@MainActor
final class ContractDetailViewModelTests: XCTestCase {

    func testLoadPopulatesDetail() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        XCTAssertEqual(vm.detail?.workflowId, "wf-1")
        XCTAssertTrue(vm.detail?.isPendingGate ?? false)
        XCTAssertNil(vm.actionError)
    }

    func testApproveSendsApproverAndReloads() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "running"))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        api.detailResult = .success(sampleDetail(state: "running"))  // reload result
        await vm.approve()
        XCTAssertEqual(api.lastApprovedId, "wf-1")
        XCTAssertEqual(api.lastApproverArg, "me@example.com")
        XCTAssertNil(vm.actionError)
    }

    func testApprove403MapsToPermissionDeniedMessage() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        api.approveResult = .failure(APIError.http(status: 403, body: ""))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.approve()
        XCTAssertEqual(vm.actionError,
                       "You don't have approval permissions for this workspace.")
    }

    func testApprove410MapsToAlreadyCompletedMessage() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        api.approveResult = .failure(APIError.http(status: 410, body: ""))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.approve()
        XCTAssertEqual(vm.actionError, "This contract has already completed.")
    }

    func testApprove429MapsToRateLimitedMessage() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        api.approveResult = .failure(APIError.http(status: 429, body: ""))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.approve()
        XCTAssertEqual(vm.actionError, "Too many actions — try again in a few seconds.")
    }

    func testAbortSendsAndReloads() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.abort()
        XCTAssertEqual(api.lastAbortedId, "wf-1")
        XCTAssertNil(vm.actionError)
    }

    private func sampleDetail(state: String) -> ContractDetail {
        ContractDetail(
            workflowId: "wf-1", contractId: nil, state: state,
            goal: "G", workspace: nil, origin: nil, plan: nil,
            ledger: [], abortReason: nil, refIds: nil, summaryTitle: nil
        )
    }
}
```

- [ ] **Step 5.2: Run the tests to verify they fail**

```bash
cd /tmp/gi-impl
xcodebuild test -project Goquest.xcodeproj -scheme GoquestUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GoquestUnitTests/ContractDetailViewModelTests 2>&1 | tail -10
```

Expected: BUILD FAILED — `ContractDetailViewModel` undefined.

- [ ] **Step 5.3: Create the ViewModel**

Create `/tmp/gi-impl/Goquest/Features/Contracts/ContractDetailViewModel.swift`:

```swift
import Foundation

@MainActor
final class ContractDetailViewModel: ObservableObject {
    @Published private(set) var detail: ContractDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isActioning = false
    @Published var loadError: String?
    @Published var actionError: String?

    let workflowId: String
    private let approver: String
    private let api: ContractsAPI

    init(workflowId: String, approver: String, api: ContractsAPI = APIClient.shared) {
        self.workflowId = workflowId
        self.approver = approver
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await api.getContract(id: workflowId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func approve() async {
        guard !isActioning else { return }
        isActioning = true
        defer { isActioning = false }
        do {
            try await api.approveContract(id: workflowId, approver: approver)
            actionError = nil
            await load()
        } catch {
            actionError = mapActionError(error)
        }
    }

    func abort() async {
        guard !isActioning else { return }
        isActioning = true
        defer { isActioning = false }
        do {
            try await api.abortContract(id: workflowId)
            actionError = nil
            await load()
        } catch {
            actionError = mapActionError(error)
        }
    }

    // Maps the three operator-relevant HTTP statuses to user-friendly copy.
    // Anything else falls through to the generic localized message.
    private func mapActionError(_ error: Error) -> String {
        if case let APIError.http(status, _) = error {
            switch status {
            case 403: return "You don't have approval permissions for this workspace."
            case 410: return "This contract has already completed."
            case 429: return "Too many actions — try again in a few seconds."
            default:  break
            }
        }
        return error.localizedDescription
    }
}
```

- [ ] **Step 5.4: Run the tests to verify they pass**

```bash
cd /tmp/gi-impl
xcodebuild test -project Goquest.xcodeproj -scheme GoquestUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GoquestUnitTests/ContractDetailViewModelTests 2>&1 | tail -10
```

Expected: 6 of 6 PASS.

- [ ] **Step 5.5: Commit (just the VM + tests; the View still depends on Task 6)**

```bash
cd /tmp/gi-impl
git add Goquest/Features/Contracts/ContractDetailViewModel.swift \
        GoquestUnitTests/ContractTests.swift
git commit -m "feat(contracts): ContractDetailViewModel with approve/abort + error mapping

6 VM tests cover happy-path load, approve+reload, abort+reload, and
the three operator-visible error statuses (403 permissions, 410 already
completed, 429 rate limited). Other errors fall through to the generic
localized message."
```

---

## Task 6: `ContractDetailView` + helper components

**Files:**
- Create: `Goquest/Features/Contracts/ContractDetailView.swift`
- Create: `Goquest/Features/Contracts/_components/GoalCard.swift`
- Create: `Goquest/Features/Contracts/_components/ApproveBar.swift`
- Create: `Goquest/Features/Contracts/_components/StepTimeline.swift`

- [ ] **Step 6.1: Create `GoalCard.swift`**

Create `/tmp/gi-impl/Goquest/Features/Contracts/_components/GoalCard.swift`:

```swift
import SwiftUI

struct GoalCard: View {
    let detail: ContractDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.summaryTitle ?? detail.goal ?? "(no goal)")
                .font(.headline)
            if let goal = detail.goal, goal != detail.summaryTitle {
                Text(goal)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            HStack(spacing: 8) {
                if let channel = detail.origin?.channel, !channel.isEmpty {
                    Label(channel, systemImage: "bubble.left.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let ws = detail.workspace, !ws.isEmpty {
                    Label(ws, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let reason = detail.abortReason, !reason.isEmpty {
                Text("Aborted: \(reason)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 6.2: Create `ApproveBar.swift`**

Create `/tmp/gi-impl/Goquest/Features/Contracts/_components/ApproveBar.swift`:

```swift
import SwiftUI

struct ApproveBar: View {
    let isBusy: Bool
    let onApprove: () -> Void
    let onAbort: () -> Void

    @State private var showAbortConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This contract requires your approval", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            HStack(spacing: 12) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isBusy)

                Button(role: .destructive) {
                    showAbortConfirm = true
                } label: {
                    Label("Abort", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
            if isBusy { ProgressView() }
        }
        .padding()
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .confirmationDialog("Abort this contract? This stops the workflow.",
                             isPresented: $showAbortConfirm, titleVisibility: .visible) {
            Button("Abort", role: .destructive, action: onAbort)
            Button("Cancel", role: .cancel) {}
        }
    }
}
```

- [ ] **Step 6.3: Create `StepTimeline.swift`**

Create `/tmp/gi-impl/Goquest/Features/Contracts/_components/StepTimeline.swift`:

```swift
import SwiftUI

struct StepTimeline: View {
    let plan: ContractPlan?
    let ledger: [ContractLedgerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Plan / Ledger").font(.headline)
            if let steps = plan?.steps, !steps.isEmpty {
                ForEach(steps) { step in
                    StepRow(step: step, ledger: ledgerEntry(for: step.stepId))
                }
            } else {
                Text("No plan yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ledgerEntry(for stepId: String) -> ContractLedgerEntry? {
        ledger.first(where: { $0.stepId == stepId })
    }
}

private struct StepRow: View {
    let step: ContractPlanStep
    let ledger: ContractLedgerEntry?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("\(step.stepId)  \(step.capability)")
                    .font(.callout)
                if let target = step.target {
                    Text("@ \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = ledger?.verdict?.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(ledger?.verdict?.passed == false ? .orange : .secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        let symbol: String
        let color: Color
        switch ledger?.status {
        case "ok":      symbol = "checkmark.circle.fill"; color = .green
        case "fail":    symbol = "xmark.circle.fill";     color = .red
        case "skipped": symbol = "minus.circle.fill";     color = .gray
        case .some:     symbol = "circle.dotted";         color = .blue
        case .none:     symbol = "circle";                color = .gray
        }
        return Image(systemName: symbol).foregroundStyle(color)
    }
}
```

- [ ] **Step 6.4: Create `ContractDetailView.swift`**

Create `/tmp/gi-impl/Goquest/Features/Contracts/ContractDetailView.swift`:

```swift
import SwiftUI

struct ContractDetailView: View {
    let workflowId: String
    @StateObject private var vm: ContractDetailViewModel

    init(workflowId: String) {
        self.workflowId = workflowId
        let approver = (AuthService.shared.userInfo["email"] as? String)
            ?? (AuthService.shared.userInfo["sub"] as? String)
            ?? ""
        _vm = StateObject(wrappedValue: ContractDetailViewModel(
            workflowId: workflowId, approver: approver))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail = vm.detail {
                    if detail.isPendingGate {
                        ApproveBar(
                            isBusy: vm.isActioning,
                            onApprove: { Task { await vm.approve() } },
                            onAbort:   { Task { await vm.abort() } }
                        )
                    }
                    if let actionError = vm.actionError {
                        Text(actionError)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    GoalCard(detail: detail)
                    StepTimeline(plan: detail.plan, ledger: detail.ledger)
                    if let refs = detail.refIds, !refs.isEmpty {
                        ReferencesList(refIds: refs)
                    }
                } else if vm.isLoading {
                    ProgressView().padding()
                } else if let err = vm.loadError {
                    Text(err).foregroundStyle(.red).padding()
                }
            }
            .padding()
        }
        .navigationTitle("Contract")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

private struct ReferencesList: View {
    let refIds: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("References").font(.headline)
            ForEach(refIds, id: \.self) { id in
                Text(id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 6.5: Build the project**

```bash
cd /tmp/gi-impl
xcodebuild build -project Goquest.xcodeproj -scheme Goquest \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED. The `NavigationLink { ContractDetailView(workflowId: …) }` reference from `ContractsView.swift` in Task 4 now resolves.

- [ ] **Step 6.6: Re-run the full unit test target — nothing should regress**

```bash
cd /tmp/gi-impl
xcodebuild test -project Goquest.xcodeproj -scheme GoquestUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10
```

Expected: all existing tests + 12 new contract tests PASS.

- [ ] **Step 6.7: Commit Task 4 + Task 6 together**

```bash
cd /tmp/gi-impl
git add Goquest/Features/Contracts/ContractsView.swift \
        Goquest/Features/Contracts/ContractDetailView.swift \
        Goquest/Features/Contracts/_components/GoalCard.swift \
        Goquest/Features/Contracts/_components/ApproveBar.swift \
        Goquest/Features/Contracts/_components/StepTimeline.swift
git commit -m "feat(contracts): ContractsView + ContractDetailView with GoalCard, ApproveBar, StepTimeline

List screen has a segmented control (Pending Gates default / Running /
Recent), pull-to-refresh, empty-state copy per queue, and rows that link
to the detail screen.

Detail screen shows ApproveBar (when gate_pending), GoalCard, and a
StepTimeline of plan steps joined with ledger entries. Approver is read
from AuthService.userInfo[email], falling back to sub.

Approve/Abort flow goes through ContractDetailViewModel; errors render
as an inline red banner above GoalCard."
```

---

## Task 7: `MainTabView` wire + UI smoke test

**Files:**
- Modify: `Goquest/Features/Inbox/MainTabView.swift`
- Modify: `GoquestUITests/SmokeUITests.swift`

- [ ] **Step 7.1: Add the new tab**

Open `/tmp/gi-impl/Goquest/Features/Inbox/MainTabView.swift`. Replace the entire body with:

```swift
import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { InboxView() }
                .tabItem { Label("Inbox", systemImage: "tray.full") }
            NavigationStack { ContractsView() }
                .tabItem { Label("Contracts", systemImage: "signature") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
```

- [ ] **Step 7.2: Add a smoke UITest assertion**

Open `/tmp/gi-impl/GoquestUITests/SmokeUITests.swift`. Find the existing smoke test method. Append a new test after it (do not modify the existing test):

```swift
    func testContractsTabRenders() {
        let app = XCUIApplication()
        app.launch()
        // Tap the Contracts tab.
        app.tabBars.buttons["Contracts"].tap()
        // Either the empty state or the list shows up; the navigation title
        // is the cheapest invariant to assert on.
        XCTAssertTrue(app.navigationBars["Contracts"].waitForExistence(timeout: 5))
    }
```

- [ ] **Step 7.3: Run unit + UI tests**

```bash
cd /tmp/gi-impl
xcodebuild test -project Goquest.xcodeproj -scheme Goquest \
  -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -15
```

Expected: all unit and UI tests pass. The new `testContractsTabRenders` PASSES (the tab exists, tapping it shows the Contracts nav title).

If the smoke test fails because the simulator isn't logged in, the empty-state branch still renders the `Contracts` nav title — the assertion holds regardless of auth state. If it fails for any other reason, fix it before commit.

- [ ] **Step 7.4: Commit**

```bash
cd /tmp/gi-impl
git add Goquest/Features/Inbox/MainTabView.swift \
        GoquestUITests/SmokeUITests.swift
git commit -m "feat(app): wire Contracts tab into MainTabView + UITest smoke

Tab sits between Inbox and Settings, uses the 'signature' SF Symbol.
The smoke test taps the tab and asserts the Contracts navigation title
renders — survives any auth state."
```

---

## Task 8: Push branch and open PR

- [ ] **Step 8.1: Push**

```bash
cd /tmp/gi-impl
git push -u origin feat/ios-contracts-approval
```

- [ ] **Step 8.2: Open the PR**

```bash
cd /tmp/gi-impl
gh pr create -R Lyckabc/goquest-ios \
  --title "feat(contracts): iOS approval-gate handling — list + detail + approve/abort" \
  --body "$(cat <<'EOF'
## Summary

New **Contracts** tab in the iOS app for handling contract-plane approval gates from the phone, without opening the web app.

## What the user sees

- New tab between Inbox and Settings.
- Three segments: **Pending Gates** (default — \`queue=awaiting_plan\`) / **Running** / **Recent**.
- Tap a row → detail with GoalCard, StepTimeline, and (when \`state=gate_pending\`) an **ApproveBar** with Approve + Abort buttons. Abort prompts with a confirmation dialog.
- Pull-to-refresh on both screens.

## Out of scope

- Push notifications + notification action buttons (backend dispatcher is still TODO).
- Live SSE event stream.
- Reject-with-reason, submission gate, WatchOS counterpart, gopedia inline restore for ref_ids.

## Spec / plan

- Spec: \`docs/superpowers/specs/2026-06-01-goquest-ios-contracts-approval-design.md\`
- Plan: \`docs/superpowers/plans/2026-06-01-goquest-ios-contracts-approval.md\`

## What changed

- \`Goquest/Models/Contract.swift\` — Codable models mirroring the goquest-ui shape.
- \`Goquest/Services/ContractsAPI.swift\` — protocol so ViewModels can mock the network.
- \`Goquest/Services/APIClient.swift\` — 4 new methods; APIClient now conforms to ContractsAPI.
- \`Goquest/Features/Contracts/\` (new): ContractsView + ContractDetailView + their ViewModels + GoalCard/ApproveBar/StepTimeline helpers.
- \`Goquest/Features/Inbox/MainTabView.swift\` — adds the tab.
- \`GoquestUnitTests/ContractTests.swift\` — 12 new tests (3 decoding + 3 list VM + 6 detail VM incl. error mapping).
- \`GoquestUITests/SmokeUITests.swift\` — 1 new smoke test for the tab.

## Verification

- Decode/list/detail/approve/abort/error-mapping unit tests pass.
- Smoke UI test passes (taps the tab, asserts Contracts nav title).
- Build clean against iOS Simulator iPhone 15.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Capture the PR URL.

---

## Self-Review

**Spec coverage:**
- New Contracts tab → Task 7 ✓
- List screen with Pending Gates / Running / Recent segments + pull-to-refresh + empty state → Tasks 3 + 4 ✓
- Detail screen with GoalCard / ApproveBar / StepTimeline → Tasks 5 + 6 ✓
- Approve / Abort actions with confirmation on abort → Task 6 (ApproveBar) + Task 5 (VM) ✓
- Three error mappings (403/410/429) → Task 5 ✓
- Approver sourced from \`AuthService.userInfo[email]\` with \`sub\` fallback → Task 6 (ContractDetailView init) ✓
- Codable models mirroring web shape → Task 1 ✓
- `ContractsAPI` protocol for test injection → Task 2 ✓
- Tests: decoding + list VM + detail VM + error mapping + smoke UI → Tasks 1, 3, 5, 7 ✓
- Out-of-scope items (push, SSE, reject-with-reason, submission gate, WatchOS, gopedia restore) → not implemented ✓

**Placeholder scan:** clean. Each code step contains the full code to paste. Each command lists the expected outcome (BUILD SUCCEEDED / N of N PASS / specific error string).

**Type consistency:**
- `ContractSummary` properties (`workflowId`, `state`, `goal`, `origin`, `workspace`, `startedAt`, …) used identically across Tasks 1 (model), 3 (VM tests + sample factory), and 4 (View render).
- `ContractDetail` properties (`workflowId`, `state`, `goal`, `origin`, `plan`, `ledger`, `abortReason`, `refIds`, `summaryTitle`) used identically across Tasks 1, 5 (VM tests + sample factory), 6 (GoalCard / StepTimeline render).
- `ContractsAPI` method signatures (`listContracts(queue:limit:)`, `getContract(id:)`, `approveContract(id:approver:)`, `abortContract(id:)`) match between Task 2 (protocol + APIClient impl), Task 3 (Mock), Task 5 (Mock), and the ViewModels.
- `APIError.http(status:body:)` case used in Task 5 mapping matches what `APIClient` already throws (verified by reading the existing `throwIfHTTPError` in `APIClient.swift`).
- `ContractsViewModel.Queue` enum and its `queryParam` property defined in Task 3 and consumed in Task 4 — matches.
- `AuthService.shared.userInfo` accessed in Task 6 matches the existing `@Published private(set) var userInfo: [String: Any]` declaration in `AuthService.swift`.
