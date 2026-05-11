import WatchKit
import UserNotifications

/// Bridges WatchKit lifecycle + notification action handling on watchOS.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        NotificationActions.registerCategories()
        WatchSession.shared.activate()
    }

    // Foreground notifications still surface a banner — without this, the
    // system suppresses them while the app is active.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Notification action handler — fires when the user taps "Complete" on
    // a Goquest ticket notification (delivered to the Watch via iPhone mirror).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationActions.handle(response: response)
    }
}
