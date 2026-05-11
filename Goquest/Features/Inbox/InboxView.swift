import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var workspaces: [Workspace] = []
    @Published var selectedWorkspace: Workspace?
    @Published var tickets: [Ticket] = []
    @Published var queue: Queue = .open
    @Published var isLoading = false
    @Published var error: String?

    enum Queue: String, CaseIterable, Identifiable {
        case open = "Open", mine = "Mine", overdue = "Overdue"
        var id: String { rawValue }
    }

    func loadWorkspaces() async {
        do {
            workspaces = try await APIClient.shared.listWorkspaces()
            if selectedWorkspace == nil, let first = workspaces.first {
                selectedWorkspace = first
                await loadTickets()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadTickets() async {
        guard let w = selectedWorkspace else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await APIClient.shared.listTickets(workspaceId: w.id, limit: 100)
            tickets = resp.tickets
        } catch {
            self.error = error.localizedDescription
        }
    }

    var filtered: [Ticket] {
        let now = Date()
        switch queue {
        case .open:
            return tickets.filter { !$0.isTerminal }
        case .mine:
            return tickets.filter { !$0.isTerminal && $0.assigneeType == "human" }
        case .overdue:
            return tickets.filter { !$0.isTerminal && ($0.dueAt ?? .distantFuture) < now }
        }
    }
}

struct InboxView: View {
    @StateObject private var vm = InboxViewModel()

    var body: some View {
        List {
            if vm.workspaces.count > 1 {
                Section {
                    Picker("Workspace", selection: Binding(
                        get: { vm.selectedWorkspace?.id ?? "" },
                        set: { newId in
                            vm.selectedWorkspace = vm.workspaces.first { $0.id == newId }
                            Task { await vm.loadTickets() }
                        }
                    )) {
                        ForEach(vm.workspaces) { w in
                            Text(w.name).tag(w.id)
                        }
                    }
                }
            }

            Section {
                Picker("Queue", selection: $vm.queue) {
                    ForEach(InboxViewModel.Queue.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .pickerStyle(.segmented)
            }

            if vm.isLoading {
                ProgressView()
            } else if vm.filtered.isEmpty {
                ContentUnavailableView("No tickets", systemImage: "tray", description: Text("\(vm.queue.rawValue) queue is empty."))
            } else {
                ForEach(vm.filtered) { t in
                    NavigationLink(value: t) {
                        TicketRow(ticket: t)
                    }
                }
            }
        }
        .navigationTitle("Inbox")
        .navigationDestination(for: Ticket.self) { t in
            TicketDetailView(ticketId: t.id, preloaded: t)
        }
        .refreshable { await vm.loadTickets() }
        .task { await vm.loadWorkspaces() }
        .alert("Error", isPresented: Binding(get: { vm.error != nil }, set: { _ in vm.error = nil })) {
            Button("OK") { vm.error = nil }
        } message: { Text(vm.error ?? "") }
    }
}

struct TicketRow: View {
    let ticket: Ticket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ticket.title).font(.body).lineLimit(2)
                Spacer()
                PriorityBadge(priority: ticket.priority)
            }
            HStack(spacing: 6) {
                StatusBadge(status: ticket.status)
                if let due = ticket.dueAt {
                    Label {
                        Text(due, style: .relative).font(.caption)
                    } icon: {
                        Image(systemName: ticket.isOverdue ? "exclamationmark.circle.fill" : "clock")
                    }
                    .foregroundStyle(ticket.isOverdue ? .red : .secondary)
                }
                if let requester = ticket.requesterName ?? ticket.requesterEmail {
                    Text("· \(requester)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
