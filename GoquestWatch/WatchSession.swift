import Foundation
import WatchConnectivity
import OSLog

private let log = Logger(subsystem: "home.toji.goquest.watch", category: "WCSession")

/// Receives the OIDC access token + a few prefs from the iPhone counterpart.
/// We cache the token in UserDefaults (watchOS local) so the Complete action
/// in a notification can run even if WCSession is mid-handshake.
@MainActor
final class WatchSession: NSObject, ObservableObject {
    static let shared = WatchSession()

    @Published private(set) var accessToken: String?
    @Published private(set) var lastSyncedAt: Date?

    private let defaults = UserDefaults.standard
    private static let tokenKey = "goquest.watch.access_token"
    private static let syncedAtKey = "goquest.watch.last_synced_at"

    var hasToken: Bool { (accessToken ?? "").isEmpty == false }

    override init() {
        super.init()
        accessToken = defaults.string(forKey: Self.tokenKey)
        if let ts = defaults.object(forKey: Self.syncedAtKey) as? Date {
            lastSyncedAt = ts
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func updateToken(_ token: String?) {
        accessToken = token
        if let t = token {
            defaults.set(t, forKey: Self.tokenKey)
        } else {
            defaults.removeObject(forKey: Self.tokenKey)
        }
        lastSyncedAt = Date()
        defaults.set(lastSyncedAt, forKey: Self.syncedAtKey)
    }
}

extension WatchSession: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error {
            log.error("activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            log.info("activation state=\(state.rawValue, privacy: .public)")
            // Pull the most recent applicationContext synchronously on launch.
            if !session.receivedApplicationContext.isEmpty {
                applyContext(session.receivedApplicationContext)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        applyContext(applicationContext)
    }

    private func applyContext(_ context: [String: Any]) {
        let token = context["access_token"] as? String
        Task { @MainActor in
            updateToken(token)
        }
    }
}
