import XCTest
@testable import Goquest

final class ModelDecodingTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601withFractionalSeconds
        return d
    }

    // 리스트 응답: risk_tier/title_name/vcs_links 전부 없어도 디코드된다.
    func testTicketDecodesWithoutNewFields() throws {
        let json = """
        {"id":"t1","title":"Old","type":"task","status":"pending","priority":"normal",
         "requester_id":"u1","created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-01T00:00:00Z"}
        """.data(using: .utf8)!
        let t = try decoder().decode(Ticket.self, from: json)
        XCTAssertNil(t.riskTier)
        XCTAssertNil(t.titleName)
        XCTAssertNil(t.vcsLinks)
    }

    // 상세 응답: 신규 필드 + vcs_links embed 디코드.
    func testTicketDecodesWithNewFieldsAndVcsLinks() throws {
        let json = """
        {"id":"t1","title":"New","type":"task","status":"in_progress","priority":"high",
         "requester_id":"u1","risk_tier":"high","title_name":"goq-sample-ticket",
         "created_at":"2026-07-01T00:00:00.123Z","updated_at":"2026-07-01T00:00:00.123Z",
         "vcs_links":[{"id":"l1","ticket_id":"t1","provider":"github",
           "repo_full_name":"tojiuni/goquest","kind":"pull_request","external_ref":"73",
           "url":"https://github.com/tojiuni/goquest/pull/73","state":"merged",
           "title":"feat: analytics","source_branch":"goq-analytics-api","target_branch":"main",
           "actor":"neunexus[bot]","created_at":"2026-07-01T00:00:00Z","updated_at":"2026-07-01T00:00:00Z"}]}
        """.data(using: .utf8)!
        let t = try decoder().decode(Ticket.self, from: json)
        XCTAssertEqual(t.riskTier, "high")
        XCTAssertEqual(t.titleName, "goq-sample-ticket")
        XCTAssertEqual(t.vcsLinks?.count, 1)
        let link = try XCTUnwrap(t.vcsLinks?.first)
        XCTAssertEqual(link.kind, "pull_request")
        XCTAssertEqual(link.repoFullName, "tojiuni/goquest")
        XCTAssertEqual(link.state, "merged")
        XCTAssertEqual(link.sourceBranch, "goq-analytics-api")
    }

    func testAnalyticsResponseDecodes() throws {
        let json = """
        {"group_by":"status","total":7,"buckets":[
          {"key":"pending","count":4},{"key":"in_progress","count":2},{"key":"","count":1}]}
        """.data(using: .utf8)!
        let r = try decoder().decode(AnalyticsResponse.self, from: json)
        XCTAssertEqual(r.groupBy, "status")
        XCTAssertEqual(r.total, 7)
        XCTAssertEqual(r.buckets.count, 3)
        XCTAssertEqual(r.buckets[0].key, "pending")
        XCTAssertEqual(r.buckets[0].count, 4)
        XCTAssertEqual(r.buckets[2].key, "")
    }
}
