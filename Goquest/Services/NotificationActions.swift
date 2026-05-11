import Foundation
import UserNotifications
import OSLog

private let log = Logger(subsystem: "home.toji.goquest", category: "Notif")

/// Single source of truth for the notification category shared with the
/// watchOS target (`GoquestWatch/NotificationActions.swift`). Register at app
/// launch on both targets so the `Complete` button shows up regardless of
/// which device receives the push.
///
/// The iPhone side also handles the action when the watch isn't worn — same
/// API call, same idempotency story.
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

    /// Run the side effect for a notification action. Only `Complete` does
    /// network work; `Open` and the default tap fall through to the system
    /// foreground handler.
    static func handle(response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let ticketId = info["ticket_id"] as? String else {
            log.warning("notification missing ticket_id")
            return
        }
        switch response.actionIdentifier {
        case completeAction:
            do {
                _ = try await APIClient.shared.patchTicketStatus(id: ticketId, status: "completed")
                log.info("completed ticket \(ticketId, privacy: .public) from notification")
            } catch {
                log.error("complete \(ticketId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        default:
            break
        }
    }
}
