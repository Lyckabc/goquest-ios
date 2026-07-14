import SwiftUI

@MainActor
final class TicketDetailViewModel: ObservableObject {
    @Published var ticket: Ticket?
    @Published var comments: [Comment] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(ticketId: String, preloaded: Ticket?) async {
        ticket = preloaded
        isLoading = true
        defer { isLoading = false }
        do {
            async let ticketTask = APIClient.shared.getTicket(id: ticketId)
            async let commentsTask = APIClient.shared.listComments(ticketId: ticketId)
            ticket = try await ticketTask
            comments = try await commentsTask
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TicketDetailView: View {
    let ticketId: String
    let preloaded: Ticket?
    @StateObject private var vm = TicketDetailViewModel()

    var body: some View {
        List {
            if let t = vm.ticket {
                Section("Meta") {
                    LabeledContent("Status") { StatusBadge(status: t.status) }
                    LabeledContent("Priority") { PriorityBadge(priority: t.priority) }
                    if let tier = t.riskTier, !tier.isEmpty {
                        LabeledContent("Risk") { RiskTierBadge(tier: tier) }
                    }
                    if let chan = t.channel {
                        LabeledContent("Channel") { Text(chan).font(.caption) }
                    }
                    if let name = t.requesterName ?? t.requesterEmail {
                        LabeledContent("Requester") { Text(name).font(.caption) }
                    }
                    if let assignee = t.assigneeId, !assignee.isEmpty {
                        LabeledContent("Assignee") { Text(assignee).font(.caption) }
                    }
                    if let due = t.dueAt {
                        LabeledContent("Due") {
                            Text(due, style: .date) + Text(" ") + Text(due, style: .time)
                        }
                        .foregroundStyle(t.isOverdue ? .red : .primary)
                    }
                }
                if let desc = t.description, !desc.isEmpty {
                    Section("Description") {
                        Text(desc).font(.body)
                    }
                }

                if let links = t.vcsLinks, !links.isEmpty {
                    Section("Development") {
                        ForEach(links) { link in
                            VcsLinkRow(link: link)
                        }
                    }
                }
            }

            Section("Conversation") {
                if vm.comments.isEmpty {
                    Text("아직 대화가 없습니다").foregroundStyle(.secondary).font(.caption)
                } else {
                    ForEach(vm.comments) { c in
                        CommentRow(comment: c)
                    }
                }
            }
        }
        .navigationTitle(vm.ticket.map { "#\(String($0.id.prefix(8)))" } ?? "Loading…")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(ticketId: ticketId, preloaded: preloaded) }
        .refreshable { await vm.load(ticketId: ticketId, preloaded: preloaded) }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { _ in vm.error = nil })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }
}

struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.authorId).font(.caption.bold())
                Text("(\(comment.authorKind))").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(comment.createdAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
            }
            if comment.isInternal {
                Label("Internal note", systemImage: "lock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text(comment.body).font(.body)
        }
        .padding(.vertical, 4)
        .listRowBackground(comment.isInternal ? Color.orange.opacity(0.05) : Color.clear)
    }
}

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
