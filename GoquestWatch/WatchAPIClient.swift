import Foundation
import OSLog

private let log = Logger(subsystem: "home.toji.goquest.watch", category: "API")

/// Minimal API client used only by the notification action handler. The full
/// REST surface lives in the iPhone target — this one needs just one verb.
actor WatchAPIClient {
    static let shared = WatchAPIClient()

    private let baseURL = "https://goquest.toji.homes/api/v1"
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func completeTicket(id: String) async {
        let token = await MainActor.run { WatchSession.shared.accessToken }
        guard let token, !token.isEmpty else {
            log.warning("complete \(id, privacy: .public): no access_token, skipping")
            return
        }
        guard let url = URL(string: "\(baseURL)/tickets/\(id)") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = #"{"status":"completed"}"#.data(using: .utf8)

        do {
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if (200...299).contains(status) {
                log.info("complete \(id, privacy: .public): ok")
            } else {
                let body = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                log.error("complete \(id, privacy: .public): http=\(status) body=\(body, privacy: .public)")
            }
        } catch {
            log.error("complete \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
