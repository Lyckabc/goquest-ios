# goquest-ios: 서버 업데이트 반영 (검색 · 새 필드 · 통계 탭 · Lymphhub 인증)

- **Date**: 2026-07-14
- **Status**: Approved (brainstorming session)
- **Scope**: goquest-service 최근 업데이트(#62~#73) 중 읽기 기능·인증을 iOS에 반영.
  쓰기 기능(티켓 생성/수정/댓글)은 이번 범위 밖 (docs/TODO.md 유지).

## 배경

goquest-service에 iOS MVP 이후 추가된 기능:

| 서버 변경 | PR | iOS 반영 |
|---|---|---|
| 풀텍스트 검색 `GET /tickets?q=` | #71 | ✅ 인박스 검색 |
| `GET /analytics/tickets?group_by=` 집계 | #73 | ✅ 통계 탭 |
| dual-JWKS (ZITADEL + Lymphhub) | #70, #62 | ✅ Lymphhub 로그인 전환 |
| `risk_tier` 필드 | #65 | ✅ 배지 표시 |
| VCS 링크 embed (`vcs_links` on GET /tickets/{id}) | #55~#69 | ✅ Development 섹션 |
| 벌크 업데이트, Idempotency-Key | #72, #63 | ❌ 쓰기 기능 범위 밖 |

## 1. Lymphhub 인증 완전 전환 — `Services/AuthService.swift`

- `issuer`: `https://auth.toji.homes` → `https://toji.idp.toji.homes` (Lymphhub, 표준 OIDC discovery + EdDSA JWT).
- `clientID`: 신규 Lymphhub native PKCE client로 교체. 하드코딩 대신 xcconfig 주입
  (`GOQUEST_OIDC_CLIENT_ID`) — TODO.md의 Bundle hygiene 항목을 이 기회에 해소.
- `redirectURI`: `home.toji.goquest://oauth2redirect/lymphhub` (스킴 동일 → Info.plist 변경 없음).
- AppAuth PKCE 흐름·Keychain persist·silent refresh·Watch 토큰 브릿지는 변경 없음.
- **마이그레이션**: 강제 로그아웃 없음. 서버가 dual-JWKS로 기존 ZITADEL 토큰을 계속
  수용하므로, 기존 세션은 refresh 실패 시점에 자연스럽게 Lymphhub 재로그인으로 유도.
- **인프라 선행 조건 (별도 티켓)**: Lymphhub에 native PKCE 앱 등록
  (redirect `home.toji.goquest://oauth2redirect/lymphhub`, grant: authorization_code +
  refresh_token, PKCE no-secret). 등록 경로: `neunexus/services/lymphhub/sso-apps.tf`.
  발급된 client_id는 Vault `secret/neunexus/sso/goquest-ios`에 기록.

## 2. 인박스 검색 — `Services/APIClient.swift` + `Features/Inbox/InboxView.swift`

- `listTickets(workspaceId:projectId:q:limit:offset:)`에 `q: String?` 추가.
  값은 `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` 적용.
- `InboxView`: `.searchable(text:)` + 300ms 디바운스(Task 취소 방식) 후 서버 호출.
  빈 검색어 → q 없이 기존 목록. 검색은 서버 풀텍스트(title/title_name/description,
  대소문자 무시 부분일치)를 그대로 사용하고 로컬 필터를 두지 않는다.
- 검색 중에도 워크스페이스/프로젝트 필터는 AND로 함께 적용된다(서버 동작 그대로).

## 3. 새 필드 표시 — `Models/Ticket.swift` + 상세 화면

- `Ticket`에 optional 필드 추가 (리스트 응답엔 없을 수 있으므로 전부 optional):
  - `riskTier: String?` (`risk_tier`)
  - `titleName: String?` (`title_name`)
  - `vcsLinks: [VcsLink]?` (`vcs_links` — GET /tickets/{id}에서만 embed)
- `VcsLink` 신규 모델 (서버 `internal/vcs/model.go` JSON 그대로):
  `id, ticket_id, provider, repo_full_name, kind(branch|pr|commit), external_ref, url,
  state, title, source_branch?, target_branch?, actor, created_at, updated_at`.
- `UI/RiskTierBadge.swift` 신설 — PriorityBadge 패턴. tier별 색상
  (예: low=gray, medium=blue, high=orange, critical=red; 서버 값 그대로 표시하고
  미지의 값은 중립색). 인박스 행 + 상세 헤더에 표시 (nil이면 숨김).
- `TicketDetailView`에 **Development 섹션**: `vcsLinks` 목록. 행마다 kind 아이콘
  (branch=arrow.triangle.branch, pr=arrow.triangle.pull.request 대체 아이콘, commit=number),
  `repo_full_name` + `external_ref`/`title`, PR이면 state(open/merged/closed) 캡슐.
  탭 → `url`을 `Link`/`openURL`로 열기. 링크 없으면 섹션 숨김.

## 4. 통계 탭 — `Features/Stats/` 신설

- `MainTabView`에 4번째 탭 **Stats** (`chart.bar.xaxis`), Inbox와 Contracts 사이 배치는
  Inbox 다음으로.
- `APIClient.ticketAnalytics(groupBy:workspaceId:status:) -> AnalyticsResponse`
  - `GET /analytics/tickets?group_by=<key>[&workspace_id=][&status=]`
  - `AnalyticsResponse { groupBy: String, buckets: [AggBucket{key, count}], total: Int }`
    (모델은 `Models/Analytics.swift`)
- `StatsView` + `StatsViewModel` (`@MainActor ObservableObject`, Inbox 패턴 재사용):
  - 워크스페이스 선택: InboxView와 동일한 selector 패턴 (nil = All).
  - status / priority / type 3회 **병렬 호출** (`async let`).
  - 상단 카드: 열린 티켓 수 = status 버킷에서 terminal(completed/cancelled/failed) 제외 합.
  - Swift Charts 가로 바 차트 3개 (status / priority / type). 빈 key("")는 "none"으로 표시.
  - 로딩/에러/빈 상태 처리 (Inbox와 동일 스타일).

## 에러 처리

- 기존 `APIError` 재사용. 검색·통계 실패는 화면 내 재시도 가능한 에러 뷰.
- `group_by` 화이트리스트 밖 요청은 클라이언트가 만들지 않으므로 400은 프로그래밍 에러로 간주.

## 테스트

- `GoquestUnitTests`:
  - Ticket 디코드: `risk_tier`/`title_name`/`vcs_links` 포함·미포함 JSON 모두.
  - `VcsLink`·`AnalyticsResponse` 디코드 (서버 JSON 픽스처).
  - listTickets URL 조립: q 인코딩(공백·한글·`&`), 필터 조합.
- 빌드·테스트 검증은 CI(Woodpecker mac agent)에서 수행 (pod에는 Xcode 없음).

## 범위 밖 (명시)

- 티켓 쓰기 기능(생성/수정/댓글), 벌크 업데이트, Idempotency-Key 활용.
- 위젯, magic-link Universal Link, per-project 캘린더 (docs/TODO.md 유지).
- Lymphhub 앱 등록 자체 (인프라 선행 티켓으로 분리).
