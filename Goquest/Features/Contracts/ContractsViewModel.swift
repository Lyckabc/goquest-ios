import Foundation

@MainActor
final class ContractsViewModel: ObservableObject {
    enum Queue: String, CaseIterable, Identifiable {
        case pendingGates = "Pending Gates"
        case running = "Running"
        case recent = "Recent"

        var id: String { rawValue }

        // Maps to the contract-plane `?queue=…` query param. `recent` sends no
        // filter so the API returns everything in created-at order.
        var queryParam: String? {
            switch self {
            case .pendingGates: return "awaiting_plan"
            case .running:      return "running"
            case .recent:       return nil
            }
        }
    }

    @Published private(set) var contracts: [ContractSummary] = []
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var selectedQueue: Queue = .pendingGates

    private let api: ContractsAPI

    init(api: ContractsAPI = ContractsAPIClient()) {
        self.api = api
    }

    func load(queue: Queue) async {
        selectedQueue = queue
        isLoading = true
        defer { isLoading = false }
        do {
            contracts = try await api.listContracts(queue: queue.queryParam, limit: 50)
        } catch {
            self.error = error.localizedDescription
            contracts = []
        }
    }
}
