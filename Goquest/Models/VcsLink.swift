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
