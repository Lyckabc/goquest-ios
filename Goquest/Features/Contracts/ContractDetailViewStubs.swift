import Foundation

// Temporary local stub for the symbol Task 5 will introduce
// (`ContractDetailViewModel`). Task 6 (this PR) needs to reference the type
// so `ContractDetailView` compiles, but Task 5 lives on a parallel branch
// that hasn't merged yet. When Task 5 lands, delete this file — the real
// implementation in `ContractDetailViewModel.swift` will take over.
//
// The surface mirrors what `ContractDetailView` actually calls: the four
// @Published properties it reads, the workflowId for display, and the three
// async methods bound to the Approve / Abort buttons + the .task / pull-to-
// refresh lifecycle. Methods are no-ops here; the view shows the loading
// state until Task 5 replaces this file.
@MainActor
final class ContractDetailViewModel: ObservableObject {
    @Published private(set) var detail: ContractDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isActioning = false
    @Published var loadError: String?
    @Published var actionError: String?

    let workflowId: String
    private let approver: String
    private let api: ContractsAPI

    init(workflowId: String, approver: String, api: ContractsAPI = ContractsAPIClient()) {
        self.workflowId = workflowId
        self.approver = approver
        self.api = api
    }

    func load() async {}
    func approve() async {}
    func abort() async {}
}
