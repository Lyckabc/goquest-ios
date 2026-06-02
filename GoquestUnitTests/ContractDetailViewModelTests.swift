import XCTest
@testable import Goquest

// MARK: - ContractDetailViewModel

@MainActor
final class ContractDetailViewModelTests: XCTestCase {

    func testLoadPopulatesDetail() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        XCTAssertEqual(vm.detail?.workflowId, "wf-1")
        XCTAssertTrue(vm.detail?.isPendingGate ?? false)
        XCTAssertNil(vm.actionError)
    }

    func testApproveSendsApproverAndReloads() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "running"))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        api.detailResult = .success(sampleDetail(state: "running"))  // reload result
        await vm.approve()
        XCTAssertEqual(api.lastApprovedId, "wf-1")
        XCTAssertEqual(api.lastApproverArg, "me@example.com")
        XCTAssertNil(vm.actionError)
    }

    func testApprove403MapsToPermissionDeniedMessage() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        api.approveResult = .failure(APIError.http(status: 403, body: ""))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.approve()
        XCTAssertEqual(vm.actionError,
                       "You don't have approval permissions for this workspace.")
    }

    func testApprove410MapsToAlreadyCompletedMessage() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        api.approveResult = .failure(APIError.http(status: 410, body: ""))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.approve()
        XCTAssertEqual(vm.actionError, "This contract has already completed.")
    }

    func testApprove429MapsToRateLimitedMessage() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        api.approveResult = .failure(APIError.http(status: 429, body: ""))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.approve()
        XCTAssertEqual(vm.actionError, "Too many actions — try again in a few seconds.")
    }

    func testAbortSendsAndReloads() async {
        let api = MockContractsAPI()
        api.detailResult = .success(sampleDetail(state: "gate_pending"))
        let vm = ContractDetailViewModel(workflowId: "wf-1", approver: "me@example.com", api: api)
        await vm.load()
        await vm.abort()
        XCTAssertEqual(api.lastAbortedId, "wf-1")
        XCTAssertNil(vm.actionError)
    }

    private func sampleDetail(state: String) -> ContractDetail {
        ContractDetail(
            workflowId: "wf-1", contractId: nil, state: state,
            goal: "G", workspace: nil, origin: nil, plan: nil,
            ledger: [], abortReason: nil, refIds: nil, summaryTitle: nil
        )
    }
}

// MARK: - MockContractsAPI
//
// Lightweight in-memory ContractsAPI mock for VM tests. Lives here (rather
// than alongside ContractsViewModel's tests) because Tasks 3/4 haven't landed
// yet — the shared mock from Task 3 will replace this when those PRs merge.
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
