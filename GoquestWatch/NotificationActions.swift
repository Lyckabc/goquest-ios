import Foundation
import UserNotifications
import OSLog

private let log = Logger(subsystem: "home.toji.goquest.watch", category: "Notif")

/// Single source of truth for the notification category shared between
/// iPhone and Watch. Register at app launch on both targets so the
/// `Complete` button shows up regardless of which device receives the push.
enum NotificationActions {
    static let ticketCategory = "GOQUEST_TICKET"
    static let completeAction = "GOQUEST_COMPLETE"
    static let openAction = "GOQUEST_OPEN"

    static func registerCategories() {
        let complete = UNNotificationAction(
            identifier: completeAction,
            title: "Complete",
            options: [.authenticationRequired]
        )
        let open = UNNotificationAction(
            identifier: openAction,
            title: "Open",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: ticketCategory,
            actions: [complete, open],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Routes a UNNotificationResponse to the right side effect. Idempotent:
    /// the goquest-service ticket.update API itself rejects status changes
    /// from terminal states, so a double-tap won't corrupt anything.
    static func handle(response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let ticketId = info["ticket_id"] as? String else {
            log.warning("notification missing ticket_id")
            return
        }
        switch response.actionIdentifier {
        case completeAction:
            await WatchAPIClient.shared.completeTicket(id: ticketId)
        case openAction, UNNotificationDefaultActionIdentifier:
            // Best-effort handoff — watchOS auto-launches the iPhone app
            // when the user taps the notification body. Nothing else to do.
            break
        default:
            break
        }
    }
}
