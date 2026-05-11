import Foundation
import EventKit

/// Kuna-style safe calendar sync. We create our own calendars
/// (`Goquest - <workspace>`) and only ever touch events we wrote
/// — never modify the user's other calendars.
@MainActor
final class CalendarSyncService: ObservableObject {
    static let shared = CalendarSyncService()

    private let store = EKEventStore()
    private let prefsKey = "goquest.calendarSync.prefs"
    private let defaults = UserDefaults.standard

    struct Prefs: Codable, Equatable {
        var isEnabled: Bool
        // workspace_id → EventKit calendar identifier (one calendar per workspace)
        var workspaceCalendars: [String: String]
        var version: Int

        static let initial = Prefs(isEnabled: false, workspaceCalendars: [:], version: 1)
    }

    @Published private(set) var prefs: Prefs = .initial
    @Published private(set) var lastSyncedAt: Date?

    init() {
        if let data = defaults.data(forKey: prefsKey),
           let decoded = try? JSONDecoder().decode(Prefs.self, from: data) {
            prefs = decoded
        }
    }

    // MARK: - Permission

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Calendar lifecycle

    /// Ensures a Goquest-owned calendar exists for the workspace and returns
    /// its identifier. Idempotent.
    func ensureCalendar(for workspace: Workspace) throws -> String {
        if let existingID = prefs.workspaceCalendars[workspace.id],
           let cal = store.calendar(withIdentifier: existingID) {
            return cal.calendarIdentifier
        }
        // Look up or create local source.
        guard let source = store.sources.first(where: { $0.sourceType == .local })
              ?? store.defaultCalendarForNewEvents?.source else {
            throw CalendarError.noSource
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "Goquest - \(workspace.name)"
        cal.source = source
        cal.cgColor = CGColor(red: 99/255, green: 102/255, blue: 241/255, alpha: 1) // indigo
        try store.saveCalendar(cal, commit: true)

        prefs.workspaceCalendars[workspace.id] = cal.calendarIdentifier
        savePrefs()
        return cal.calendarIdentifier
    }

    func disableSync(deleteEvents: Bool = false) throws {
        if deleteEvents {
            for (_, calID) in prefs.workspaceCalendars {
                guard let cal = store.calendar(withIdentifier: calID) else { continue }
                try store.removeCalendar(cal, commit: true)
            }
        }
        prefs = .initial
        savePrefs()
    }

    /// Nuke every event Goquest has written to iOS Calendar, leaving the
    /// per-workspace calendar shells in place so a subsequent sync re-fills
    /// them. Use this when the user wants to clean up pollution (e.g.
    /// stale test events) without resetting their workspace mapping.
    ///
    /// Returns the number of events removed.
    @discardableResult
    func purgeAllEvents() throws -> Int {
        var removed = 0
        for (_, calID) in prefs.workspaceCalendars {
            guard let cal = store.calendar(withIdentifier: calID) else { continue }
            let pred = store.predicateForEvents(
                withStart: .distantPast, end: .distantFuture, calendars: [cal]
            )
            for ev in store.events(matching: pred) {
                try store.remove(ev, span: .thisEvent, commit: false)
                removed += 1
            }
        }
        try store.commit()
        return removed
    }

    // MARK: - Event sync

    /// Replaces all existing Goquest events on the workspace's calendar with
    /// the supplied tickets. Tickets without `due_at` are skipped.
    func sync(workspace: Workspace, tickets: [Ticket]) throws {
        guard prefs.isEnabled else { return }
        let calID = try ensureCalendar(for: workspace)
        guard let cal = store.calendar(withIdentifier: calID) else {
            throw CalendarError.calendarMissing
        }

        // Remove all our existing events on this calendar (we own it).
        let pred = store.predicateForEvents(
            withStart: Date.distantPast,
            end: Date.distantFuture,
            calendars: [cal]
        )
        for ev in store.events(matching: pred) {
            try store.remove(ev, span: .thisEvent, commit: false)
        }

        // Insert one event per ticket with a due_at.
        for ticket in tickets where ticket.dueAt != nil && !ticket.isTerminal {
            let ev = EKEvent(eventStore: store)
            ev.calendar = cal
            ev.title = "[\(ticket.priority)] \(ticket.title)"
            ev.notes = "ticket://\(ticket.id)\n\(ticket.description ?? "")"
            ev.url = URL(string: "home.toji.goquest://tickets/\(ticket.id)")
            ev.startDate = ticket.dueAt!
            ev.endDate = ticket.dueAt!.addingTimeInterval(30 * 60) // 30-min slot
            ev.isAllDay = false
            try store.save(ev, span: .thisEvent, commit: false)
        }

        try store.commit()
        lastSyncedAt = Date()
    }

    /// Fetches workspaces + their tickets from goquest-service and runs
    /// `sync(workspace:tickets:)` for each. Used by Settings → Sync now AND
    /// by the background refresh task — keeps the trigger paths sharing one
    /// idempotent implementation.
    func syncAllWorkspaces() async throws -> Int {
        guard prefs.isEnabled else { return 0 }
        let workspaces = try await APIClient.shared.listWorkspaces()
        for ws in workspaces {
            let resp = try await APIClient.shared.listTickets(workspaceId: ws.id, limit: 200)
            try sync(workspace: ws, tickets: resp.tickets)
        }
        return workspaces.count
    }

    // MARK: - Settings ergonomics

    func enableSync() {
        prefs.isEnabled = true
        savePrefs()
    }

    private func savePrefs() {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: prefsKey)
        }
    }
}

enum CalendarError: Error, LocalizedError {
    case noSource, calendarMissing, accessDenied
    var errorDescription: String? {
        switch self {
        case .noSource: return "No EventKit source available"
        case .calendarMissing: return "Stored calendar reference is gone"
        case .accessDenied: return "Calendar access denied"
        }
    }
}
