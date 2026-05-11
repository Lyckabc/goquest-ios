import Foundation
import AppAuth
import KeychainAccess
import UIKit
import OSLog

private let log = Logger(subsystem: "home.toji.goquest", category: "Auth")

/// ZITADEL OIDC PKCE wrapper. Persists the OIDAuthState in Keychain so
/// silent refresh works across launches.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    enum State { case loading, loggedOut, loggedIn }
    @Published private(set) var state: State = .loading
    @Published private(set) var userInfo: [String: Any] = [:]

    private let keychain = Keychain(service: "home.toji.goquest.auth")
    private let stateKey = "oidAuthState"

    // ZITADEL config — provisioned via lymphhub Terraform (sso-apps.tf → goquest_ios).
    // Vault path: secret/neunexus/sso/goquest-ios (client-id).
    // To rotate, edit lymphhub and re-apply; the value below mirrors the current state.
    private let issuer = URL(string: "https://auth.toji.homes")!
    private let clientID = "372400414877936855"
    // Use double-slash custom scheme form. iOS 18+'s URL parser canonicalises
    // single-slash forms inconsistently across ASWebAuthenticationSession and
    // CFNetwork, which can break the redirect_uri exact-match in OAuth.
    private let redirectURI = URL(string: "home.toji.goquest://oauth2redirect/zitadel")!

    private var authState: OIDAuthState? {
        didSet { persist() }
    }
    private var currentFlow: OIDExternalUserAgentSession?

    func bootstrap() async {
        if let data = try? keychain.getData(stateKey),
           let restored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) {
            authState = restored
            state = restored.isAuthorized ? .loggedIn : .loggedOut
        } else {
            state = .loggedOut
        }
    }

    func login(presenting: UIViewController) async throws {
        let config = try await discover()
        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: clientID,
            // AppAuth-iOS exposes constants for openid/profile/email/phone/address only.
            // `offline_access` (needed for refresh tokens) is passed as a raw string.
            scopes: [OIDScopeOpenID, OIDScopeProfile, OIDScopeEmail, "offline_access"],
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            currentFlow = OIDAuthState.authState(byPresenting: request, presenting: presenting) { [weak self] state, error in
                if let state {
                    self?.authState = state
                    self?.state = .loggedIn
                    cont.resume()
                } else {
                    // Detailed logging via os_log so simctl log stream captures it.
                    if let nsErr = error as NSError? {
                        log.error("login failed: domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code, privacy: .public)")
                        log.error("  description=\(nsErr.localizedDescription, privacy: .public)")
                        for (k, v) in nsErr.userInfo {
                            log.error("  userInfo[\(String(describing: k), privacy: .public)] = \(String(describing: v), privacy: .public)")
                        }
                    } else {
                        log.error("login failed: state and error both nil")
                    }
                    cont.resume(throwing: error ?? AuthError.unknown)
                }
            }
        }
    }

    func handleCallback(url: URL) {
        if let flow = currentFlow, flow.resumeExternalUserAgentFlow(with: url) {
            currentFlow = nil
        }
    }

    func logout() {
        try? keychain.remove(stateKey)
        authState = nil
        state = .loggedOut
    }

    /// Returns a valid access token, refreshing silently if needed.
    func accessToken() async throws -> String {
        guard let auth = authState else { throw AuthError.notLoggedIn }
        return try await withCheckedThrowingContinuation { cont in
            auth.performAction { (accessToken: String?, _: String?, error: Error?) in
                if let t = accessToken {
                    cont.resume(returning: t)
                } else {
                    cont.resume(throwing: error ?? AuthError.unknown)
                }
            }
        }
    }

    var userId: String? {
        authState?.lastTokenResponse?.idToken.flatMap(extractSubject(idToken:))
    }

    // MARK: - Internals

    private func discover() async throws -> OIDServiceConfiguration {
        try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) { config, error in
                if let c = config { cont.resume(returning: c) }
                else { cont.resume(throwing: error ?? AuthError.discoveryFailed) }
            }
        }
    }

    private func persist() {
        guard let auth = authState else {
            try? keychain.remove(stateKey)
            return
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: auth, requiringSecureCoding: true) {
            try? keychain.set(data, key: stateKey)
        }
    }

    private func extractSubject(idToken: String) -> String? {
        // JWT payload is the middle segment; we only need `sub`.
        let parts = idToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
        // base64url → base64 padding
        payload = payload.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["sub"] as? String
    }
}

enum AuthError: Error, LocalizedError {
    case notLoggedIn, discoveryFailed, unknown
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "Not signed in"
        case .discoveryFailed: return "ZITADEL discovery failed"
        case .unknown: return "Unknown auth error"
        }
    }
}
