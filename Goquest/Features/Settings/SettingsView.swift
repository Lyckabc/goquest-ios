import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @ObservedObject var calendar = CalendarSyncService.shared
    @ObservedObject var push = PushService.shared

    @State private var workspaces: [Workspace] = []
    @State private var syncStatusMessage: String?
    @State private var pushStatusMessage: String?
    @State private var showPurgeConfirm = false

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
                // Always surface the destructive action. Hiding it behind a
                // pre-flight check on `hasAnyGoquestCalendar` requires
                // EventKit read access, which the user may not have granted
                // — same place where the events to delete actually live.
                // The action itself requests authorization, then no-ops if
                // there is genuinely nothing to remove (reports "0 events").
                Button(role: .destructive) {
                    showPurgeConfirm = true
                } label: {
                    Label("Delete all Goquest events from iPhone Calendar",
                          systemImage: "trash")
                }
                if let msg = syncStatusMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            .confirmationDialog(
                "Delete all Goquest events?",
                isPresented: $showPurgeConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete events only", role: .destructive) {
                    Task { await purgeEvents(removeCalendars: false) }
                }
                Button("Delete events + calendars", role: .destructive) {
                    Task { await purgeEvents(removeCalendars: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes events Goquest wrote to your iOS Calendar. Calendars themselves are kept unless you choose otherwise.")
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

    private func purgeEvents(removeCalendars: Bool) async {
        do {
            // Ensure we have full-access to delete — read-only access can't
            // remove events. Triggers the prompt if the user has never granted.
            if calendar.authorizationStatus != .fullAccess {
                _ = try await calendar.requestAccess()
            }
            let eventCount = try calendar.purgeAllEvents()
            if removeCalendars {
                let calCount = try calendar.removeAllGoquestCalendars()
                try calendar.disableSync(deleteEvents: false) // prefs reset; events/cals already gone
                BackgroundCalendarSync.shared.cancelPendingRefresh()
                syncStatusMessage = "Removed \(eventCount) events and \(calCount) calendars."
            } else {
                syncStatusMessage = "Removed \(eventCount) events. Calendars are still in place."
            }
        } catch {
            syncStatusMessage = "Purge failed: \(error.localizedDescription)"
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
