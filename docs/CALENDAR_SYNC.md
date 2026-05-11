# Calendar Sync — Spec

Modelled on [trykuna/app's calendar_sync_spec.md](https://github.com/trykuna/app/blob/main/calendar_sync_spec.md), adapted to goquest's workspace model.

## Scope

- One **Goquest-owned** EventKit calendar per workspace, titled `Goquest - <workspaceName>`.
- Only sync tickets with `due_at` and `status NOT IN ('completed','cancelled','failed')`.
- Never edit calendars or events outside our own.
- Full replace on each sync (simpler than diff; ticket count per workspace is small).

## User flow

1. Settings → **Calendar Sync** toggle ON.
2. App requests `EKEventStore.requestFullAccessToEvents()` (iOS 17+ API).
3. On grant: app creates `Goquest - <workspace>` calendars on first sync.
4. App pulls tickets per workspace from goquest-service and writes events.
5. Subsequent toggles or "Sync now" button replay the same flow.

## Data model

```swift
struct CalendarSyncPrefs: Codable {
    var isEnabled: Bool
    // workspace_id → EKCalendar.calendarIdentifier
    var workspaceCalendars: [String: String]
    var version: Int   // schema version (start at 1)
}
```

Persisted in `UserDefaults` under key `goquest.calendarSync.prefs`.

## Event mapping

| Field | Source |
|-------|--------|
| `title` | `[priority] <ticket.title>` |
| `notes` | `ticket://<id>\n<description>` |
| `url` | `home.toji.goquest://tickets/<id>` (deep link) |
| `startDate` | `ticket.dueAt` |
| `endDate` | `ticket.dueAt + 30min` |
| `isAllDay` | false |
| `calendar` | workspace-owned EKCalendar |

## Safety invariants

1. **Own-calendar-only**: `EKEventStore.calendar(withIdentifier:)` lookup must succeed against an identifier WE persisted. If missing, recreate; never adopt an arbitrary existing calendar.
2. **No cross-workspace events**: each ticket's event lives only on its workspace's calendar.
3. **Disable preserves user data by default**: turning sync off leaves calendars and events intact unless the user explicitly chooses "Remove events".

## Out of scope (TODO)

- Per-project calendars
- Single combined calendar mode
- Recurring task → recurring event mapping
- Smart conflict resolution (e.g. ticket moved between workspaces)
