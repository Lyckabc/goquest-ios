import Foundation

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

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await api.getContract(id: workflowId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func approve() async {
        guard !isActioning else { return }
        isActioning = true
        defer { isActioning = false }
        do {
            try await api.approveContract(id: workflowId, approver: approver)
            actionError = nil
            await load()
        } catch {
            actionError = mapActionError(error)
        }
    }

    func abort() async {
        guard !isActioning else { return }
        isActioning = true
        defer { isActioning = false }
        do {
            try await api.abortContract(id: workflowId)
            actionError = nil
            await load()
        } catch {
            actionError = mapActionError(error)
        }
    }

    // Maps the three operator-relevant HTTP statuses to user-friendly copy.
    // Anything else falls through to the generic localized message.
    private func mapActionError(_ error: Error) -> String {
        if case let APIError.http(status, _) = error {
            switch status {
            case 403: return "You don't have approval permissions for this workspace."
            case 410: return "This contract has already completed."
            case 429: return "Too many actions — try again in a few seconds."
            default:  break
            }
        }
        return error.localizedDescription
    }
}
