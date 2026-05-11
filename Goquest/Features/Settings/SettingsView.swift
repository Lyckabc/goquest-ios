import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var calendar = CalendarSyncService.shared
    @ObservedObject var push = PushService.shared

    @State private var workspaces: [Workspace] = []
    @State private var syncStatusMessage: String?
    @State private var pushStatusMessage: String?

    var body: some View {
        List {
            Section("Calendar Sync") {
                Toggle("Enable Calendar Sync", isOn: Binding(
                    get: { calendar.prefs.isEnabled },
                    set: { newValue in
                        Task { await toggleCalendarSync(newValue) }
                    }
                ))
                if calendar.prefs.isEnabled {
                    Text("Goquest creates one calendar per workspace (`Goquest - <workspace>`) and only edits events it owns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let last = calendar.lastSyncedAt {
                        LabeledContent("Last sync") {
                            Text(last, style: .relative).font(.caption)
                        }
                    }
                    Button("Sync now") {
                        Task { await syncNow() }
                    }
                }
                if let msg = syncStatusMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Push Notifications") {
                LabeledContent("Status") {
                    Text(pushStatusLabel).font(.caption)
                }
                if push.authStatus == .notDetermined || push.authStatus == .denied {
                    Button("Enable push notifications") {
                        Task { await enablePush() }
                    }
                }
                if let msg = pushStatusMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Account") {
                if let uid = auth.userId {
                    LabeledContent("User") {
                        Text(uid).font(.caption.monospaced()).lineLimit(1)
                    }
                }
                Button(role: .destructive) {
                    auth.logout()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await push.refreshAuthStatus()
            await loadWorkspaces()
        }
    }

    private var pushStatusLabel: String {
        switch push.authStatus {
        case .authorized:    return "Authorized"
        case .denied:        return "Denied (open Settings to enable)"
        case .provisional:   return "Provisional"
        case .ephemeral:     return "Ephemeral"
        case .notDetermined: return "Not requested yet"
        @unknown default:    return "Unknown"
        }
    }

    private func toggleCalendarSync(_ on: Bool) async {
        if on {
            do {
                let granted = try await calendar.requestAccess()
                guard granted else {
                    syncStatusMessage = "Calendar access denied. Enable in Settings → Privacy → Calendars."
                    return
                }
                calendar.enableSync()
                await syncNow()
                BackgroundCalendarSync.shared.scheduleNextRefresh()
            } catch {
                syncStatusMessage = error.localizedDescription
            }
        } else {
            do { try calendar.disableSync(deleteEvents: false) }
            catch { syncStatusMessage = error.localizedDescription }
            BackgroundCalendarSync.shared.cancelPendingRefresh()
        }
    }

    private func syncNow() async {
        do {
            let n = try await calendar.syncAllWorkspaces()
            syncStatusMessage = "Synced \(n) workspaces."
            // Manual sync also re-arms the background refresh task so the
            // next system-driven sync stays scheduled.
            BackgroundCalendarSync.shared.scheduleNextRefresh()
        } catch {
            syncStatusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    private func loadWorkspaces() async {
        do {
            workspaces = try await APIClient.shared.listWorkspaces()
        } catch {
            // Silent: settings still usable without workspace data.
        }
    }

    private func enablePush() async {
        do {
            let granted = try await push.requestAuthorization()
            pushStatusMessage = granted ? "Notifications enabled." : "Notifications denied."
        } catch {
            pushStatusMessage = error.localizedDescription
        }
    }
}
