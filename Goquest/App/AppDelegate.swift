import UIKit
import UserNotifications

/// Bridges UIKit's APNs callbacks to PushService. SwiftUI apps still need a
/// UIApplicationDelegateAdaptor for these methods.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // BGTaskScheduler.register MUST run before launch finishes. The
        // matching identifier is declared in Info.plist under
        // BGTaskSchedulerPermittedIdentifiers.
        Task { @MainActor in BackgroundCalendarSync.shared.register() }
        UNUserNotificationCenter.current().delegate = self
        NotificationActions.registerCategories()
        Task { @MainActor in PhoneWatchBridge.shared.activate() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { await PushService.shared.didRegister(deviceToken: token) }
    }
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushService.shared.didFailToRegister(error: error)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationActions.handle(response: response)
    }
}
