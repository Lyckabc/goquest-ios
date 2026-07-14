import XCTest
@testable import Goquest

final class APIPathTests: XCTestCase {

    func testTicketsPathDefault() {
        XCTAssertEqual(APIPath.tickets(workspaceId: nil, projectId: nil, q: nil, limit: 50, offset: 0),
                       "/tickets?limit=50&offset=0")
    }

    func testTicketsPathAllFilters() {
        XCTAssertEqual(
            APIPath.tickets(workspaceId: "w1", projectId: "p1", q: nil, limit: 100, offset: 0),
            "/tickets?limit=100&offset=0&workspace_id=w1&project_id=p1")
    }

    // q는 percent-encode된다: 공백, &, 한글.
    func testTicketsPathEncodesQuery() {
        let path = APIPath.tickets(workspaceId: nil, projectId: nil, q: "빌드 fix&deploy", limit: 50, offset: 0)
        XCTAssertEqual(path, "/tickets?limit=50&offset=0&q=%EB%B9%8C%EB%93%9C%20fix%26deploy")
    }

    // 빈/공백-만 q는 생략된다.
    func testTicketsPathOmitsBlankQuery() {
        XCTAssertEqual(APIPath.tickets(workspaceId: nil, projectId: nil, q: "  ", limit: 50, offset: 0),
                       "/tickets?limit=50&offset=0")
    }

    func testAnalyticsPath() {
        XCTAssertEqual(APIPath.ticketAnalytics(groupBy: "status", workspaceId: "w1"),
                       "/analytics/tickets?group_by=status&workspace_id=w1")
        XCTAssertEqual(APIPath.ticketAnalytics(groupBy: "priority", workspaceId: nil),
                       "/analytics/tickets?group_by=priority")
    }
}
