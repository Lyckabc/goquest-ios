import SwiftUI
import UserNotifications

@main
struct GoquestWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .onAppear {
                    session.activate()
                    NotificationActions.registerCategories()
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject var session: WatchSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Goquest")
                    .font(.headline)

                if session.hasToken {
                    Label("Linked to iPhone", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Open Goquest on iPhone to sign in", systemImage: "iphone.gen3")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                if let last = session.lastSyncedAt {
                    Text("Last sync: \(last, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 4)

                Text("Goquest taps land here as wrist notifications. Long-press a notification to complete a ticket without opening your phone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
    }
}
