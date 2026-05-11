import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var workspaces: [Workspace] = []
    /// `nil` means "All workspaces" — fetches tickets cross-workspace.
    @Published var selectedWorkspace: Workspace?
    @Published var projects: [Project] = []
    /// `nil` means "All projects in the current workspace selection".
    /// Forced to `nil` whenever `selectedWorkspace == nil` (All) because the
    /// project list endpoint is workspace-scoped.
    @Published var selectedProject: Project?
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
            // Default to the first workspace if none chosen yet; user can
            // switch to "All" via the picker once data is loaded.
            if selectedWorkspace == nil, let first = workspaces.first {
                selectedWorkspace = first
                await loadProjects()
            }
            await loadTickets()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectWorkspace(_ ws: Workspace?) async {
        selectedWorkspace = ws
        selectedProject = nil   // project list is workspace-scoped
        projects = []
        await loadProjects()
        await loadTickets()
    }

    func selectProject(_ project: Project?) async {
        selectedProject = project
        await loadTickets()
    }

    private func loadProjects() async {
        guard let w = selectedWorkspace else { return }
        do {
            projects = try await APIClient.shared.listProjects(workspaceId: w.id)
        } catch {
            // Non-fatal — projects picker just stays empty.
            projects = []
        }
    }

    func loadTickets() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await APIClient.shared.listTickets(
                workspaceId: selectedWorkspace?.id,
                projectId: selectedProject?.id,
                limit: 100
            )
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

    // Sentinel string tag for the "All workspaces" picker option. Distinct from
    // any UUID so it cannot collide with a real workspace id.
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

                    // Project picker — only meaningful within a single workspace.
                    // The list endpoint is workspace-scoped, so we hide it when
                    // the user picked "All workspaces".
                    if vm.selectedWorkspace != nil && !vm.projects.isEmpty {
                        Picker("Project", selection: Binding(
                            get: { vm.selectedProject?.id ?? "" },
                            set: { newId in
                                let target = newId.isEmpty
                                    ? nil
                                    : vm.projects.first { $0.id == newId }
                                Task { await vm.selectProject(target) }
                            }
                        )) {
                            Text("All projects").tag("")
                            ForEach(vm.projects) { p in
                                Text(p.name).tag(p.id)
                            }
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
