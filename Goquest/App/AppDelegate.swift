import UIKit

/// Bridges UIKit's APNs callbacks to PushService. SwiftUI apps still need a
/// UIApplicationDelegateAdaptor for these methods.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // BGTaskScheduler.register MUST run before launch finishes. The
        // matching identifier is declared in Info.plist under
        // BGTaskSchedulerPermittedIdentifiers.
        Task { @MainActor in BackgroundCalendarSync.shared.register() }
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
}
