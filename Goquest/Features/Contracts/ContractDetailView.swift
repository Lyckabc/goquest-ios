import SwiftUI

struct ContractDetailView: View {
    let workflowId: String
    @StateObject private var vm: ContractDetailViewModel

    // MainActor-isolated so AuthService.shared.userInfo (also @MainActor) can
    // be read synchronously here. SwiftUI calls View inits on the main thread,
    // so this annotation matches the real call site.
    @MainActor
    init(workflowId: String) {
        self.workflowId = workflowId
        let approver = (AuthService.shared.userInfo["email"] as? String)
            ?? (AuthService.shared.userInfo["sub"] as? String)
            ?? ""
        _vm = StateObject(wrappedValue: ContractDetailViewModel(
            workflowId: workflowId, approver: approver))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail = vm.detail {
                    if detail.isPendingGate {
                        ApproveBar(
                            isBusy: vm.isActioning,
                            onApprove: { Task { await vm.approve() } },
                            onAbort:   { Task { await vm.abort() } }
                        )
                    }
                    if let actionError = vm.actionError {
                        Text(actionError)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    GoalCard(detail: detail)
                    StepTimeline(plan: detail.plan, ledger: detail.ledger)
                    if let refs = detail.refIds, !refs.isEmpty {
                        ReferencesList(refIds: refs)
                    }
                } else if vm.isLoading {
                    ProgressView().padding()
                } else if let err = vm.loadError {
                    Text(err).foregroundStyle(.red).padding()
                }
            }
            .padding()
        }
        .navigationTitle("Contract")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}

private struct ReferencesList: View {
    let refIds: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("References").font(.headline)
            ForEach(refIds, id: \.self) { id in
                Text(id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
