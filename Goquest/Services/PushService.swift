import Foundation
import UserNotifications
import UIKit

/// Handles APNs token capture + registration with goquest backend.
/// MVP scope: register the token; backend dispatcher (server-side push send)
/// is tracked in `docs/ios-apns-dispatcher-todo.md` in the goquest repo.
@MainActor
final class PushService: NSObject, ObservableObject {
    static let shared = PushService()

    @Published private(set) var authStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastTokenRegistered: String?

    func refreshAuthStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = s.authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
        await refreshAuthStatus()
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }

    /// Called from AppDelegate when APNs returns a token.
    func didRegister(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        do {
            _ = try await APIClient.shared.registerDevice(apnsToken: hex, appVersion: appVersion)
            lastTokenRegistered = hex
        } catch {
            // Quiet failure — we'll retry on next launch.
            print("push: register failed: \(error)")
        }
    }

    /// Called from AppDelegate when APNs registration fails.
    func didFailToRegister(error: Error) {
        print("push: APNs registration error: \(error)")
    }
}
