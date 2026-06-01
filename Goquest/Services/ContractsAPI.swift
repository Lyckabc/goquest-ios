import Foundation

// Protocol surface for the contracts subset of the goquest API. ViewModels
// depend on this so tests can inject a mock without touching URLSession.
// `ContractsAPIClient` is the production implementation.
protocol ContractsAPI {
    func listContracts(queue: String?, limit: Int) async throws -> [ContractSummary]
    func getContract(id: String) async throws -> ContractDetail
    func approveContract(id: String, approver: String) async throws
    func abortContract(id: String) async throws
}
