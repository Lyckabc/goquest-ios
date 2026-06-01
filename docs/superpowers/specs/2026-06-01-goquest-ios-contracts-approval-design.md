# goquest-ios — contracts approval gate handling

**Status**: approved
**Date**: 2026-06-01
**Scope**: iOS-only (pull-based). Push notifications + dispatcher are tracked as a separate follow-up spec.

## Problem

`goquest-ui` (web) already surfaces contract-plane workflows in `pages/contracts/`: list, detail, plan timeline, live event stream, references, and an `ApproveBar` for the `gate_pending` state. `goquest-ios` doesn't expose any of this. Operators today must open the web app on their phone or laptop just to approve or abort a workflow that's blocking on a human decision. Mobile-native handling of approval gates is the highest-value mobile use case for contracts.

This spec adds iOS support **focused on the approval gate**: list pending gates, see enough goal context to decide, approve or abort, done. Live event streaming, reject-with-reason, submission-stage gate, and push notifications are deferred.

## Goals

- A new top-level **Contracts** tab in the app's tab bar.
- Default view shows only `state=gate_pending` contracts — "what needs my action right now".
- A user can pivot to **Running** and **Recent** without leaving the tab.
- Detail view gives enough context (goal text, origin, plan, ledger so far) to decide.
- One-tap **Approve** and **Abort** from the detail view when the workflow is `gate_pending`. Abort confirms before sending.
- Errors map to user-readable messages for the three failure modes operators will actually hit (403, 410, 429).

## Non-goals

- Push notifications, notification action buttons, dispatcher integration. (Backend dispatcher is still TODO per `goquest/docs/ios-apns-dispatcher-todo.md`.)
- Live SSE event stream. Pull-to-refresh suffices for the approval-gate use case and avoids the battery cost of a long-lived stream on iOS.
- Reject-with-reason. The web's `ApproveBar` only ships Approve / Abort today; iOS matches that surface.
- Submission gate (`/goals/{id}/submission-approve`). The plan gate (`/contracts/{id}/approve`) is the common case.
- Gopedia inline markdown restore for `ref_ids`. iOS lists the refs as text + opens in the web for now.
- WatchOS counterpart for contracts.

## Architecture

```
                                  ┌────────────────────────────────────────┐
MainTabView                       │ Inbox  │  Contracts (NEW)  │ Settings  │
                                  └────────────────────────────────────────┘
                                                  │
                                                  ▼
ContractsView                ─── segmented control: Pending Gates │ Running │ Recent
  ContractsViewModel.load(state)                                 │
    └─ APIClient.listContracts(state, limit) ─────────────────► GET /api/v1/contracts?state=…
                                                  │
                                  Tap row         ▼
ContractDetailView           ───  goal text, plan, ledger, refs, ApproveBar
  ContractDetailViewModel.load(id) → APIClient.getContract(id) ► GET /api/v1/contracts/{id}
    └─ approve()  → APIClient.approveContract(id)              ► POST /api/v1/contracts/{id}/approve
    └─ abort()    → APIClient.abortContract(id) (alert first)  ► POST /api/v1/contracts/{id}/abort
```

`goquest` (backend) already proxies these endpoints to `contract-plane`. The iOS client talks only to goquest, with the existing ZITADEL OIDC bearer token plumbed through `APIClient.authedRequest`.

## Components

### iOS source layout

- `Goquest/Features/Contracts/` (new directory)
  - `ContractsView.swift` — list + segmented control
  - `ContractDetailView.swift` — detail screen
  - `ContractsViewModel.swift` — `@MainActor` `ObservableObject`, list state + load
  - `ContractDetailViewModel.swift` — detail state + approve/abort actions
  - `_components/`
    - `GoalCard.swift` — goal text + state badge + origin chip
    - `ApproveBar.swift` — Approve + Abort buttons with loading state
    - `StepTimeline.swift` — plan/ledger merge as a `List` of `StepRow`
- `Goquest/Models/`
  - `Contract.swift` — `ContractSummary`, `ContractDetail`, `ContractPlanStep`, `ContractLedgerEntry` (all `Codable`)
- `Goquest/Services/APIClient.swift` — extended with the four new methods (see Public API)
- `Goquest/Features/Inbox/MainTabView.swift` — add the new tab
- `GoquestUnitTests/ContractTests.swift` — new test file (mirrors `TicketTests.swift` patterns)

### Public API (APIClient)

```swift
func listContracts(state: String?, limit: Int) async throws -> [ContractSummary]
func getContract(id: String) async throws -> ContractDetail
func approveContract(id: String) async throws -> Data         // body: { approver: <email> }
func abortContract(id: String) async throws -> Data           // empty body
```

`approver` is read from `AuthService.shared.userInfo["email"] as? String` (the OIDC userInfo response — ZITADEL ships `email` whenever the `email` scope is requested, which `AuthService` already does). The backend cross-checks against contract-plane admin authz. If the email claim is missing (unexpected), the call falls back to `userInfo["sub"]`; the backend rate-limits per approver id, so the choice matters only for permission lookup.

### Data models (Codable)

`ContractSummary` (list row)
- `workflow_id: String`, `contract_id: String`
- `state: String` — one of `"planning" | "gate_pending" | "running" | "done" | "aborted" | "unknown"`
- `goal: String`, `workspace: String`
- `origin: ContractOrigin { channel: String, actor: String }`
- `risk_tier: String`, `step_count: Int`
- `started_at: Date?`, `updated_at: Date?`

`ContractDetail` (detail screen)
- All summary fields plus
- `plan: ContractPlan? { steps: [ContractPlanStep], risk_tier: String?, max_steps: Int? }`
- `ledger: [ContractLedgerEntry]` — `{ step_id, status, verdict?{ passed, reason }, evidence? }`
- `abort_reason: String?`
- `ref_ids: [String]?`

`ContractPlanStep`
- `step_id: String`, `capability: String`, `target: String?`, `payload: [String: AnyCodable]?`

The web's `ContractDetail` uses these same shapes so the wire format already exists; iOS just adds Swift mirrors.

## Data flow

**List load**

1. `ContractsView.onAppear` → `vm.load(.pendingGates)`.
2. ViewModel sets `isLoading = true`, calls `APIClient.listContracts(state: "gate_pending", limit: 50)`.
3. Response decoded to `[ContractSummary]`. Sort: `updated_at` desc.
4. User pulls to refresh → same path. User switches segmented control → `vm.load(newSegment.queryState)`.

**Detail load**

1. Row tap pushes `ContractDetailView(id:)`.
2. `vm.load()` calls `APIClient.getContract(id)`. Response decoded to `ContractDetail`.
3. If `detail.state == "gate_pending"` → show `ApproveBar` at the top.

**Approve action**

1. Tap **Approve** → `ApproveBar` sets `busy = .approve`.
2. `vm.approve()` calls `APIClient.approveContract(id)`.
3. On success: show a transient toast "Approved", re-call `vm.load()` to pick up the new state. The bar disappears because state moves out of `gate_pending`.
4. On failure: map the error to a banner (see Error handling).

**Abort action**

1. Tap **Abort** → SwiftUI `.confirmationDialog` ("Abort this contract? This stops the workflow.").
2. Confirm → `vm.abort()` calls `APIClient.abortContract(id)`.
3. On success: toast "Aborted", `vm.load()`. State now `"aborted"`.
4. On failure: banner.

## Error handling

| HTTP | Cause | iOS message |
|------|------|------|
| 403 | Caller lacks `contract_plane.admin` | "You don't have approval permissions for this workspace." |
| 410 | Workflow already completed (not signalable) | "This contract has already completed." + auto-reload to sync state |
| 429 | Rate-limited (5 calls / min per approver) | "Too many actions — try again in a few seconds." |
| 401 | Token expired / missing | Existing `APIClient` already triggers re-auth via `AuthService`. Re-attempt after auth completes. |
| other | Generic | `error.localizedDescription` |

ViewModel surface: `@Published var actionError: String?` is set in the catch path; the view displays an antd-style inline `Banner` (red) below the `ApproveBar`. Dismissible.

## Testing

`GoquestUnitTests/ContractTests.swift`:

- **List**: `loadPendingGatesSucceeds`, `loadEmpty`, `loadNetworkError` — mock `APIClient` returning canned responses (use the same protocol-injection pattern `TicketTests` uses).
- **Detail load**: `detailDecodesAllFields`, `detailWithoutPlan` — verifies optional fields default sensibly.
- **Approve**: `approveSendsCorrectBody` (asserts `approver` matches the authed email), `approveSuccessReloads`.
- **Abort**: `abortSendsEmptyBody`, `abortSuccessReloads`.
- **Error mapping**: `approve403_setsPermissionDenied`, `approve410_setsAlreadyCompleted_andReloads`, `approve429_setsRateLimited` — exercise the three `HTTPStatusError` branches.

No snapshot UI tests for v1; existing app has no snapshot harness and adding one is out of scope. The `GoquestUITests` smoke test gets a new line that taps the Contracts tab and asserts the empty-state copy renders.

## Out-of-scope / future specs

- **iOS push for gate_pending**: APNs dispatcher + notification category + foreground handling. Blocks on goquest backend dispatcher (`goquest/docs/ios-apns-dispatcher-todo.md`).
- **Live SSE event stream** on the detail screen.
- **Reject with reason** (`POST /api/v1/contracts/{id}/reject` body `{approver, reason, stage}`).
- **Submission gate**: `/goals/{id}/submission-approve` / `/goals/{id}/reject`. Same UI shape, different endpoint set.
- **WatchOS counterpart** — surface the same gate-pending alert on the watch face.
- **Gopedia inline restore** for `ref_ids` on iOS detail.

## Rollout

- Single PR on `Lyckabc/goquest-ios`. No backend or web changes required (proxy endpoints already exist).
- TestFlight build after merge for manual smoke against `https://goquest.toji.homes/api/v1` with a known gate-pending workflow.
