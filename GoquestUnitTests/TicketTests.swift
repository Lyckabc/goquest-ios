import XCTest
@testable import Goquest

final class TicketTests: XCTestCase {
    func testIsTerminal() {
        for status in ["completed", "cancelled", "failed"] {
            let t = sample(status: status)
            XCTAssertTrue(t.isTerminal, "\(status) should be terminal")
        }
        let active = sample(status: "in_progress")
        XCTAssertFalse(active.isTerminal)
    }

    func testIsOverdue() {
        let past = Date().addingTimeInterval(-3600)
        let future = Date().addingTimeInterval(3600)
        XCTAssertTrue(sample(status: "assigned", dueAt: past).isOverdue)
        XCTAssertFalse(sample(status: "assigned", dueAt: future).isOverdue)
        // completed tickets shouldn't be overdue even if due_at is past.
        XCTAssertFalse(sample(status: "completed", dueAt: past).isOverdue)
    }

    private func sample(status: String, dueAt: Date? = nil) -> Ticket {
        Ticket(
            id: "t1", title: "Test", description: nil, type: "task",
            status: status, priority: "normal",
            assigneeType: nil, assigneeId: nil, requesterId: "u1",
            projectId: nil, channel: nil,
            requesterName: nil, requesterEmail: nil,
            dueAt: dueAt, createdAt: Date(), updatedAt: Date(),
            completedAt: nil, rewardXp: nil
        )
    }
}
