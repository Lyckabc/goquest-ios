# Goquest iOS

> Minimal-scope iOS companion app for [Goquest](https://github.com/tojiuni/goquest). MVP is **read-only** plus iOS Calendar sync and APNs push token registration.

| | |
|--|--|
| **Bundle ID** | `home.toji.goquest` |
| **Min iOS** | 17.0 |
| **Language** | Swift 5.10 / SwiftUI |
| **Auth** | Lymphhub OIDC PKCE (legacy ZITADEL fallback) via [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) |
| **Calendar sync** | Per-workspace EventKit calendars (Kuna pattern) |
| **Push** | APNs token capture + registration only — server dispatcher tracked in `tojiuni/goquest/docs/ios-apns-dispatcher-todo.md` |

---

## Setup

```bash
brew install xcodegen
xcodegen generate
open Goquest.xcodeproj
```

1. Set your Apple Developer team in **Signing & Capabilities**.
2. Add capabilities:
   - **Push Notifications**
   - **Background Modes → Remote notifications** (optional, for silent push later)
3. Set `GOQUEST_OIDC_CLIENT_ID` (xcconfig) to the Lymphhub client_id so it's injected into
   Info.plist as `GoquestOIDCClientID` — see `AuthService.swift`. Leaving it unset/unexpanded
   falls back to the legacy ZITADEL client so the app still builds and logs in during the
   migration.

### Lymphhub OIDC app

Register a new native PKCE app in Lymphhub (`https://toji.idp.toji.homes`):
- Redirect URI: `home.toji.goquest://oauth2redirect/lymphhub`
- Grant types: `authorization_code`, `refresh_token`
- Response type: `code`
- Auth method: none (PKCE, no secret)

Add this to `neunexus/services/lymphhub/sso-apps.tf` (see Vault path
`secret/neunexus/sso/goquest-ios` once Terraform applies it), then set
`GOQUEST_OIDC_CLIENT_ID` in the app's `.xcconfig` to that client_id.

goquest-service trusts both Lymphhub and legacy ZITADEL via dual-JWKS during
the migration, so existing ZITADEL sessions keep working until this app is
registered and the client_id is wired in.

---

## Project layout

```
Goquest/
  App/             # @main entry + UIApplicationDelegate
  Models/          # Workspace, Project, Ticket, Comment Codables
  Services/        # APIClient, AuthService, CalendarSyncService, PushService
  Features/
    Auth/          # LoginView
    Inbox/         # MainTabView, InboxView
    TicketDetail/  # TicketDetailView, CommentRow
    Settings/      # Calendar sync toggle, push toggle, sign-out
  UI/              # PriorityBadge, StatusBadge
  Utils/
  Resources/
docs/
  TODO.md          # deferred features
  CALENDAR_SYNC.md # workspace-based sync spec
```

---

## MVP feature list

- [x] ZITADEL OIDC PKCE login + token persistence (Keychain)
- [x] Workspace selector + Inbox queue tabs (Open / Mine / Overdue)
- [x] Ticket detail (meta + Conversation, including is_internal indicator)
- [x] Calendar sync (per-workspace EventKit calendars, safe — only edits own events)
- [x] APNs token registration → POST /devices/register
- [ ] Push delivery (server-side, see `tojiuni/goquest/docs/ios-apns-dispatcher-todo.md`)

See `docs/TODO.md` for the deferred backlog.

---

## Architecture notes

- **Auth state** lives in `AuthService.shared` (`ObservableObject`). The
  app's `RootView` switches between `LoginView` and `MainTabView` based on
  `auth.state`.
- **API client** is an `actor` so concurrent requests serialise their
  auth header lookup. Access tokens come from `AuthService.accessToken()`
  which silently refreshes via AppAuth's `performAction`.
- **Calendar sync** never writes to user calendars. We create our own
  `Goquest - <workspace>` calendars and replace all events on each sync.
- **Push** captures the APNs token via `UIApplicationDelegate` (bridged
  to SwiftUI via `@UIApplicationDelegateAdaptor`) and POSTs it to
  `/api/v1/devices/register`. The server stores it in `device_tokens`
  but does not yet dispatch pushes.

---

## CI

GitHub Actions runs `xcodegen generate` + `xcodebuild test` on the
default simulator on every push. See `.github/workflows/ci.yml`.
