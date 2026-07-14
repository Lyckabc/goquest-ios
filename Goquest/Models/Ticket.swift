import Foundation

struct Ticket: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let type: String
    let status: String
    let priority: String
    let assigneeType: String?
    let assigneeId: String?
    let requesterId: String
    let projectId: String?
    let channel: String?
    let requesterName: String?
    let requesterEmail: String?
    let dueAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let rewardXp: Int?
    let riskTier: String?
    let titleName: String?
    /// Embedded only on GET /tickets/{id}; absent (nil) in list responses.
    let vcsLinks: [VcsLink]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, type, status, priority
        case assigneeType = "assignee_type"
        case assigneeId = "assignee_id"
        case requesterId = "requester_id"
        case projectId = "project_id"
        case channel
        case requesterName = "requester_name"
        case requesterEmail = "requester_email"
        case dueAt = "due_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case rewardXp = "reward_xp"
        case riskTier = "risk_tier"
        case titleName = "title_name"
        case vcsLinks = "vcs_links"
    }

    var isTerminal: Bool {
        status == "completed" || status == "cancelled" || status == "failed"
    }

    var isOverdue: Bool {
        guard let due = dueAt, !isTerminal else { return false }
        return due < Date()
    }
}

struct TicketListResponse: Codable {
    let tickets: [Ticket]
    let total: Int
    let limit: Int
    let offset: Int
}

struct Comment: Codable, Identifiable, Hashable {
    let id: String
    let ticketId: String
    let authorId: String
    let authorKind: String
    let body: String
    let isInternal: Bool
    let isDraft: Bool?
    let gardenerScore: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ticketId = "ticket_id"
        case authorId = "author_id"
        case authorKind = "author_kind"
        case body
        case isInternal = "is_internal"
        case isDraft = "is_draft"
        case gardenerScore = "gardener_score"
        case createdAt = "created_at"
    }
}

struct CommentListResponse: Codable {
    let comments: [Comment]
}
