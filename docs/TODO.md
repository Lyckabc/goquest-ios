# iOS App — TODO (post-MVP)

> MVP shipped: read-only views, Calendar sync, APNs token registration.
> Everything below is deferred to a follow-up PR / phase.

## Write features

- [ ] **Comment write** — Reply composer + internal-note toggle (mirror web `ReplyComposer.tsx`)
- [ ] **Ticket edit** — change status, priority, assignee, due_at
- [ ] **Ticket create** — `+` button → form (workspace/project defaults from current selection)

## Customer flow

- [ ] **Magic-link Universal Link** — opening a `https://goquest.toji.homes/auth/magic-link?token=…` link in Safari should launch the app. Needs:
  - Apple-App-Site-Association file on goquest-ui nginx
  - `apple-app-site-association` entitlement
  - `application(_:continue:restorationHandler:)` to exchange the token via `POST /auth/magic-link/exchange`
- [ ] **Customer-only mode** — if logged in via magic-link, restrict UI to `/helpdesk/tickets/:id` view (no inbox, no workspace selector)

## APNs server-side

- See `tojiuni/goquest/docs/ios-apns-dispatcher-todo.md` — APNs Auth Key, push dispatcher, payload templates.

## Widgets (WidgetKit)

- [ ] **Inbox count widget** — small widget showing open ticket count for current workspace
- [ ] **Overdue list widget** — medium widget listing 3 most-overdue tickets
- Both poll backend via shared App Group; refresh on schedule.

## Better calendar sync

- [ ] **Per-project calendars** — Kuna offers Single + Per-project + Workspace modes. We currently only do Workspace. Add Single + Per-project in Settings.
- [ ] **Recurring task events** — when goquest supports recurring tickets
- [ ] **Reminder offset** — user-configurable "1 hour before due" alarm on each event

## Quality

- [ ] **Snapshot tests** for `InboxView`, `TicketDetailView`, `LoginView`
- [ ] **Integration test** against a staging goquest-service
- [ ] **Crashlytics / Sentry** integration
- [ ] **localisation** (en + ko initially)

## Bundle hygiene

- [x] Move `clientID` to an `.xcconfig` file (GoquestOIDCClientID Info.plist key — 2026-07-14)
- [ ] Add `Debug.xcconfig` / `Release.xcconfig` for environment switching
- [ ] App Store launch checklist (privacy policy, App Store screenshots)
