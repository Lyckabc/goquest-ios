import Foundation
import WatchConnectivity
import OSLog

private let log = Logger(subsystem: "home.toji.goquest", category: "WCSession")

/// iPhone-side WatchConnectivity. Pushes the current OIDC access_token to the
/// paired Watch whenever it changes (or on app launch / token refresh), so the
/// Watch can answer notification actions like "Complete ticket" without a
/// separate login.
///
/// Uses `updateApplicationContext` — a small, replace-on-write blob that
/// reaches the Watch on its next wake-up. We never use it for high-volume
/// transfers; one short JWT fits comfortably.
@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject {
    static let shared = PhoneWatchBridge()

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let s = session else { return }
        s.delegate = self
        s.activate()
    }

    /// Push the latest access_token to the Watch. Safe to call repeatedly; only
    /// invokes the WC API when the value actually changed since the last push.
    func pushAccessToken(_ token: String) {
        guard let s = session, s.activationState == .activated else { return }
        let payload: [String: Any] = ["access_token": token]
        // The applicationContext is sticky — replacing it overwrites the prior
        // value, so we don't accumulate stale tokens.
        do {
            let existing = s.applicationContext["access_token"] as? String
            guard existing != token else { return }
            try s.updateApplicationContext(payload)
            log.info("pushed access_token to Watch (\(token.count, privacy: .public) chars)")
        } catch {
            log.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension PhoneWatchBridge: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let error {
            log.error("activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            log.info("activation state=\(state.rawValue, privacy: .public)")
            // On fresh activation, opportunistically push the current token if
            // we already have one cached. Won't fire if user isn't signed in.
            Task { @MainActor in
                if let token = try? await AuthService.shared.accessToken() {
                    pushAccessToken(token)
                }
            }
        }
    }

    // Required protocol stubs — Apple's API surface still wants these on iOS
    // even when we don't care about reachability transitions.
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so we keep talking to a freshly paired Watch.
        session.activate()
    }
}
