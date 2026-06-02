import Foundation

// Wire shapes for the contracts subset of the goquest API. Field names mirror
// the contract-plane proxy responses (snake_case JSON) and match the web's
// contractPlaneApi.ts definitions. Most fields are optional so a partial
// response from an older backend still decodes.

struct ContractOrigin: Codable, Hashable {
    let channel: String?
    let actor: String?
}

struct ContractSummary: Codable, Identifiable, Hashable {
    let workflowId: String
    let contractId: String?
    let state: String
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

    // Shared decoder configured for the backend's ISO-8601-with-fractional-
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

extension ContractSummary {
    var displayTitle: String {
        if let t = summaryTitle, !t.isEmpty { return t }
        if let t = firstTicketTitle, !t.isEmpty { return t }
        if let t = goal, !t.isEmpty { return t }
        return "(No Title)"
    }
}
