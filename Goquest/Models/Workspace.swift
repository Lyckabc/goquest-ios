import Foundation

struct Workspace: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let kind: String?
}

struct WorkspaceListResponse: Codable {
    let workspaces: [Workspace]
}

struct Project: Codable, Identifiable, Hashable {
    let id: String
    let workspaceId: String
    let name: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId = "workspace_id"
        case name
        case description
    }
}

struct ProjectListResponse: Codable {
    let projects: [Project]
}
