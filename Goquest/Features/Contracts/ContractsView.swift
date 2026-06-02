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
