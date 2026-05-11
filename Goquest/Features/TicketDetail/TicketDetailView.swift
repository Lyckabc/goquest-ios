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
