import XCTest
@testable import Goquest

// MARK: - ContractsViewModel

@MainActor
final class ContractsViewModelTests: XCTestCase {

    func testLoadPopulatesContracts() async {
        let api = MockContractsAPI()
        api.listResult = .success([
            sampleSummary(id: "wf-1", goal: "G1"),
            sampleSummary(id: "wf-2", goal: "G2"),
        ])
        let vm = ContractsViewModel(api: api)
        await vm.load(queue: .pendingGates)
        XCTAssertEqual(vm.contracts.count, 2)
        XCTAssertEqual(vm.contracts.first?.workflowId, "wf-1")
        XCTAssertNil(vm.error)
        XCTAssertEqual(api.lastQueueArg, "awaiting_plan")
    }

    func testLoadEmpty() async {
        let api = MockContractsAPI()
        api.listResult = .success([])
        let vm = ContractsViewModel(api: api)
        await vm.load(queue: .pendingGates)
        XCTAssertTrue(vm.contracts.isEmpty)
        XCTAssertNil(vm.error)
    }

    func testLoadNetworkErrorSetsErrorMessage() async {
        let api = MockContractsAPI()
        api.listResult = .failure(NSError(domain: "net", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "offline"]))
        let vm = ContractsViewModel(api: api)
        await vm.load(queue: .pendingGates)
        XCTAssertTrue(vm.contracts.isEmpty)
        XCTAssertNotNil(vm.error)
    }

    private func sampleSummary(id: String, goal: String) -> ContractSummary {
        ContractSummary(
            workflowId: id, contractId: nil, state: "gate_pending",
            goal: goal, workspace: nil, origin: nil, riskTier: nil,
            stepCount: nil, startedAt: nil, updatedAt: nil,
            summaryTitle: nil, firstTicketTitle: nil,
            workspaceName: nil, projectName: nil
        )
    }
}

// Lightweight in-memory ContractsAPI mock for VM tests.
final class MockContractsAPI: ContractsAPI {
    var listResult: Result<[ContractSummary], Error> = .success([])
    var detailResult: Result<ContractDetail, Error> = .failure(NSError(domain: "test", code: 0))
    var approveResult: Result<Void, Error> = .success(())
    var abortResult: Result<Void, Error> = .success(())

    private(set) var lastQueueArg: String?
    private(set) var lastApproverArg: String?
    private(set) var lastApprovedId: String?
    private(set) var lastAbortedId: String?

    func listContracts(queue: String?, limit: Int) async throws -> [ContractSummary] {
        lastQueueArg = queue
        return try listResult.get()
    }
    func getContract(id: String) async throws -> ContractDetail {
        try detailResult.get()
    }
    func approveContract(id: String, approver: String) async throws {
        lastApprovedId = id
        lastApproverArg = approver
        return try approveResult.get()
    }
    func abortContract(id: String) async throws {
        lastAbortedId = id
        return try abortResult.get()
    }
}
