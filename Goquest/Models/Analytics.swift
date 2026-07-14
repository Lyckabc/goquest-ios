import Foundation

/// One row of GET /analytics/tickets: group key + count.
/// An empty key means the grouped column was NULL/empty on the server.
struct AggBucket: Codable, Hashable {
    let key: String
    let count: Int
}

struct AnalyticsResponse: Codable {
    let groupBy: String
    let buckets: [AggBucket]
    let total: Int

    enum CodingKeys: String, CodingKey {
        case groupBy = "group_by"
        case buckets, total
    }
}
