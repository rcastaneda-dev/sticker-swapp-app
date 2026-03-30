# CLAUDE.md — Sticker Swapp (World Cup 2026)

## Project Overview

Mobile platform for 2026 FIFA World Cup Panini-style sticker collecting. Users track their 980-sticker collection, discover nearby traders via geolocation, and execute swaps through a Tinder-style matching UI with real-time chat. The app must be live before the June 11, 2026 tournament kickoff.

**Core loop:** Track → Discover → Trade

## Tech Stack

| Layer              | Technology                                  |
|--------------------|---------------------------------------------|
| Mobile             | Flutter (Dart 3.11.1+), Riverpod, GoRouter  |
| Backend            | Go 1.26.1, Chi router, pgx                  |
| Database           | Supabase (PostgreSQL 17 + PostGIS)           |
| Real-time Chat     | Ably Pro (WebSocket) — NOT Supabase Realtime |
| Push Notifications | OneSignal + FCM                              |
| CI/CD              | GitHub Actions → TestFlight + Play Store     |

## Project Structure

```
sticker-swapp-app/
├── flutter_app/           # iOS & Android client
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── core/          # App-wide: router, services
│   │   │   └── services/
│   │   │       ├── attestation_service.dart          # Play Integrity / App Attest tokens
│   │   │       ├── attested_http_client.dart         # http.BaseClient with attestation headers
│   │   │       ├── certificate_pinner.dart           # SPKI SHA-256 pin validation
│   │   │       ├── device_integrity_service.dart     # Root/jailbreak detection (safe_device)
│   │   │       ├── device_integrity_http_client.dart # http.BaseClient with X-Device-Integrity header
│   │   │       ├── pinned_http_client.dart           # http.BaseClient with pinning
│   │   │       └── push_notification_service.dart
│   │   ├── features/      # Feature modules (auth, chat, matching, stickers)
│   │   │   ├── auth/
│   │   │   │   ├── data/
│   │   │   │   │   ├── services/auth_service.dart
│   │   │   │   │   ├── providers/auth_providers.dart
│   │   │   │   │   └── providers/guest_migration_providers.dart
│   │   │   │   ├── presentation/screens/login_screen.dart
│   │   │   │   ├── presentation/screens/guest_migration_screen.dart
│   │   │   │   └── auth.dart              # Barrel export
│   │   │   ├── stickers/
│   │   │   │   ├── data/
│   │   │   │   │   ├── models/sticker.dart
│   │   │   │   │   ├── services/sticker_service.dart
│   │   │   │   │   ├── services/guest_storage_service.dart
│   │   │   │   │   ├── providers/sticker_providers.dart
│   │   │   │   │   ├── providers/guest_inventory_providers.dart
│   │   │   │   │   └── providers/collection_progress_providers.dart
│   │   │   │   ├── presentation/screens/sticker_catalog_screen.dart
│   │   │   │   ├── presentation/screens/collection_progress_screen.dart
│   │   │   │   └── stickers.dart          # Barrel export
│   │   │   ├── chat/
│   │   │   │   ├── data/services/
│   │   │   │   └── presentation/screens/
│   │   │   └── matching/
│   │   │       └── presentation/screens/
│   │   │           ├── matches_screen.dart     # Main hub (under-13 guard)
│   │   │           └── match_screen.dart       # Trade match (under-13 guard)
│   │   └── shared/        # Cross-cutting widgets & utils
│   │       ├── theme/
│   │       │   ├── swapp_colors.dart      # Light & dark ColorScheme
│   │       │   ├── swapp_typography.dart   # Montserrat + Inter text theme
│   │       │   ├── swapp_tokens.dart       # Spacing, radius, elevation
│   │       │   ├── swapp_theme.dart        # ThemeData assembly
│   │       │   └── theme_provider.dart     # Riverpod ThemeMode toggle
│   │       ├── widgets/
│   │       │   ├── swapp_card.dart         # Card (filled/elevated/outlined)
│   │       │   ├── swapp_button.dart       # Button (primary/secondary/outlined)
│   │       │   ├── swapp_progress_bar.dart # Collection progress bar
│   │       │   └── swapp_restricted_empty_state.dart # Under-13 feature gate
│   │       └── shared.dart                 # Barrel export
│   └── test/
├── go_service/            # Backend trading engine
│   ├── cmd/server/        # Entry point (main.go)
│   └── internal/
│       ├── api/           # HTTP handlers & routes
│       ├── ably/          # Token generation (HMAC-signed)
│       ├── attestation/   # Play Integrity + App Attest verification
│       ├── middleware/    # Auth, age gating, rate limiting, attestation, device integrity, trade limiting
│       ├── db/            # pgx connection pool
│       ├── auth/          # (reserved)
│       ├── matchmaking/   # Scoring engine, in-memory cache
│       ├── ws/            # WebSocket connection manager (goroutine-per-connection)
│       └── trades/        # (reserved)
├── supabase/              # Migrations & Edge Functions
│   ├── migrations/
│   └── functions/
├── .github/workflows/     # CI/CD pipelines
├── Makefile
└── .env
```

## Quick Commands

```bash
make dev       # Run Go service on :8080 (sources .env automatically)
make test      # Run Go tests
make migrate   # Reset local Supabase DB (supabase db reset)
```

Flutter:
```bash
cd flutter_app && flutter analyze   # Lint
cd flutter_app && flutter test      # Widget tests
cd flutter_app && flutter run \     # Run app (requires --dart-define for auth)
  --dart-define=SUPABASE_URL=https://hieuxypdjrdweznedjsm.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-key> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id> \
  --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>
```

## Architecture Decisions

- **Ably over Supabase Realtime**: Supabase Realtime has a 500-connection default limit. Ably Pro handles 50K concurrent WebSocket connections needed at tournament peak.
- **Go backend (not Edge Functions)**: Supabase Edge Functions have a 2s CPU limit. The matchmaking engine and trade execution need long-running goroutines and PostgreSQL advisory locks.
- **Token-based Ably auth**: Go service validates Supabase JWT → issues HMAC-SHA256-signed Ably `TokenRequest` scoped to specific channels (least privilege). Ably SDK auto-renews via `authCallback`.
- **PostGIS for proximity**: GiST-indexed `geography(point, 4326)` on `user_locations` for O(log n) nearest-neighbor queries.
- **Riverpod for state management**: Chosen over BLoC/Provider for compile-safe dependency injection and testability.

## Auth Flow

**Providers:** Email/password, Google (native), Apple (native)

```
Email:  Flutter → signUp/signInWithPassword → Supabase Auth → JWT (15-min)
Google: Flutter → google_sign_in SDK → ID token → signInWithIdToken → Supabase Auth → JWT
Apple:  Flutter → sign_in_with_apple SDK → ID token + nonce → signInWithIdToken → Supabase Auth → JWT
All:    JWT → Age verification gate → Go validates via /auth/v1/user → Signs scoped Ably TokenRequest → WebSocket connected
```

JWT expiry: 15 min (900s in config.toml) with refresh token rotation (10s reuse interval). Ably token TTL: 1 hour.

**Auth state:** `authStateProvider` (Riverpod `NotifierProvider<AuthStateNotifier, AppAuthState>`). Sealed type: `AuthAuthenticated | AuthUnauthenticated`. Router redirects unauthenticated users to `/login`.

**Age verification gate:** After signup/sign-in (all providers), the router checks `ageVerifiedProvider`. Users without `age_verified_at` in their JWT metadata are redirected to `/age-verification`, which presents a neutral DOB picker ("When's your birthday?"). On confirmation, the server-side `verify_age()` RPC calculates `is_under_13` and stamps `age_verified_at`. Both fields are immutable once set (enforced by DB trigger in migration `0009`). The `is_under_13` flag is mirrored to user metadata for JWT-based checks by the Go middleware.

**Auto user profile:** Migration `0008` creates a `user_profiles` row via trigger on `auth.users` INSERT. `is_under_13` defaults to `false` until age verification is completed.

**Parental consent gate (under-13):** After age verification identifies a user as under-13, the router checks `needsParentalConsentProvider` and redirects to `/parental-consent`. The user enters their parent's email, which triggers `request_parental_consent()` RPC (generates a cryptographic token, 7-day expiry) and the `send-consent-email` Edge Function. The parent receives an email with a link to the `confirm-consent` Edge Function (web page). On confirmation, `confirm_parental_consent()` RPC stamps `parental_consent_at` on `user_profiles` and mirrors it to user metadata. The Flutter screen polls every 30s and auto-navigates on consent. Both `parental_consent_at` and `parent_email` are immutable once set (enforced by the `prevent_under13_mutation()` trigger extended in migration `0010`).

**Login screen** (`/login`): `ConsumerStatefulWidget` with three auth methods — email/password, Google (native), Apple (iOS only). Per-method loading states (email, Google, Apple independent). `Form` with validation (email format regex, password required, 6-char minimum on sign-up). Sign-in/sign-up toggle, display name field in sign-up mode, password visibility toggle, forgot password flow (`resetPassword`), and "Continue as Guest" link to `/catalog`.

**Guest migration screen** (`/guest-migration`): After age verification, if the user has local guest inventory, the router redirects to `/guest-migration`. Four states: prompt (shows sticker count, Transfer/Skip), migrating (progress indicator), success (items written count, Continue), error (message, Retry/Skip). Calls `migrateGuestInventory()` on `AuthService` which invokes the `migrate-guest-inventory` Edge Function. On success, clears local inventory. On skip or completion, `guestMigrationCompleteProvider` advances the router. Device UUID for idempotency is generated via `GuestStorageService.getOrCreateDeviceUuid()` (UUID v4, persisted in secure storage).

**Router redirect logic:**
0. Not authenticated + on `/catalog` or `/catalog/*` → allowed (guest browsing)
1. Not authenticated → `/login`
2. Authenticated + not age-verified → `/age-verification`
3. Authenticated + age-verified + has local guest inventory + migration not complete → `/guest-migration`
4. Authenticated + age-verified + under-13 + no parental consent → `/parental-consent`
5. Authenticated + age-verified + (13+ OR has parental consent) → `/matches` (main app)

## Sticker Catalog

**Route:** `/catalog` — browse the full 980-sticker album with filters.

**Data flow:** `StickerService` → Supabase `stickers` table (public read, RLS) → `stickerListProvider` (FutureProvider, re-fetches on filter change).

**Filters** (managed by `stickerFilterProvider` NotifierProvider):
- **Type:** FilterChip row — All / Players / Stadiums / Legends
- **Team:** Bottom sheet picker with search — 48 teams + "All Teams"

**Performance (120 FPS target):**
- `CustomScrollView` + `SliverGrid` with builder delegate — only visible tiles are built
- `RepaintBoundary` on each grid tile, `addAutomaticKeepAlives: false` for memory efficiency
- `CachedNetworkImage` (via `SwappStickerImage`) for image caching and lazy loading
- Responsive column count (3–6) via `LayoutBuilder`

**Providers:**
- `stickerServiceProvider` — StickerService singleton
- `stickerFilterProvider` — NotifierProvider for filter state (team, type)
- `stickerListProvider` — FutureProvider<List<Sticker>> (watches filter)
- `teamListProvider` — FutureProvider<List<String>> for team picker
- `guestStorageServiceProvider` — GuestStorageService singleton (encrypted local storage)
- `guestInventoryProvider` — AsyncNotifierProvider<Set<int>> for guest check/uncheck state

## Collection Progress

**Route:** `/catalog/progress` — visualize overall and per-team collection completion. Accessible via bar chart icon in the catalog AppBar.

**Overall progress hero:** Elevated `SwappCard` displaying animated percentage, sticker count text, and a `SwappProgressBar` (16px height). Values update reactively as stickers are toggled. `AnimatedSwitcher` provides fade+slide transitions on count changes.

**Per-team breakdown:** `SliverList` of 48 teams (+ "Special" for teamless stickers), each row showing team color circle (via `TeamColors`), team name, compact `SwappProgressBar` colored with the team's primary color, and owned/total count. Sorted by completion percentage descending.

**Providers:**
- `allStickersProvider` — FutureProvider<List<Sticker>> for full 980-sticker catalog (unfiltered, cached independently from `stickerListProvider`)
- `teamProgressProvider` — Provider<List<TeamProgress>> grouping stickers by team with owned/total counts, sorted by completion %
- `overallProgressProvider` — Provider<({int owned, int total})> for total collection stats

**Real-time updates:** All widgets watch `guestInventoryProvider` through derived providers — toggling a sticker in the catalog immediately updates progress bars and counts on the progress screen.

## Guest Mode & Migration

**Guest mode:** Users can track stickers locally without an account. Inventory is stored in encrypted local storage on-device (no server PII). Guest users cannot access discovery, trading, or chat features.

**Local storage (GuestStorageService):** Uses `flutter_secure_storage` (AES-256-GCM on native, localStorage on web) to persist a `Set<int>` of owned sticker IDs as encrypted JSON. A first-launch flag via `SharedPreferences` detects reinstall and wipes stale iOS Keychain data — ensuring inventory does NOT survive uninstall/reinstall. `GuestStorageService.init()` is called once in `main()` before `runApp`.

**Providers:**
- `guestStorageServiceProvider` — GuestStorageService singleton
- `guestInventoryProvider` — AsyncNotifierProvider<GuestInventoryNotifier, Set<int>>. Loads from encrypted storage; `toggleSticker(id)` flips owned/not-owned and writes through.

**UI integration:** Sticker catalog grid tiles show owned stickers at full opacity with a green check badge; unowned stickers are dimmed (40% opacity). Tapping a tile toggles ownership. A `SwappProgressBar` above the grid shows collection progress (owned / 980).

**Guest-to-member migration:** When a guest signs up, the Flutter client sends their local inventory to the `migrate-guest-inventory` Edge Function (authenticated POST). The Edge Function validates the payload and delegates to the `migrate_guest_inventory()` SECURITY DEFINER RPC.

**Migration flow:**
```
Flutter (post-signup) → migrate-guest-inventory Edge Function → migrate_guest_inventory() RPC → user_inventory upsert
```

**Idempotency:** Two tiers prevent duplicate data:
1. Migration-level: `guest_migrations` table with UNIQUE (device_uuid, user_id). Repeat calls return the previous result.
2. Item-level: `user_inventory` UNIQUE (user_id, sticker_id) with ON CONFLICT DO UPDATE.

**Conflict resolution** (when cloud inventory already has the sticker):
- Status priority: DUPLICATE > OWNED > NEEDED (higher wins)
- Quantity: `GREATEST(local, cloud)` (larger value wins)

## Real-time Channels

| Channel Pattern                     | Permissions              | Purpose            |
|-------------------------------------|--------------------------|---------------------|
| `match:{matchId}`                   | publish, subscribe, presence, history | Trade chat |
| `user:{userId}:notifications`       | subscribe only           | Server-pushed alerts |

## API Endpoints (Go Service)

| Method | Path                | Auth   | Attestation | Rate Limit | Description                    |
|--------|---------------------|--------|-------------|------------|--------------------------------|
| GET    | `/healthz`          | None   | None        | None       | DB connectivity check          |
| POST   | `/api/v1/ably/auth` | JWT    | Required    | 120/min    | Issue scoped Ably token        |
| GET    | `/api/v1/matches`   | JWT    | Required    | 120/min    | Scored match discovery         |
| GET    | `/api/v1/ws`        | JWT    | None        | 30/min     | WebSocket upgrade (1 conn/user)|

Rate limits: 120 req/min (authenticated), 30 req/min (guest). Returns 429 with `Retry-After: 60`.

## Matchmaking Engine

**Endpoint:** `GET /api/v1/matches?lat=X&lng=Y&radius=Z`

**Scoring formula:** `Proximity × 0.5 + Reciprocal × 0.3 + Activity × 0.2`

**Sub-scores (all normalized [0,1]):**
- **Proximity:** `1 - (distance_m / radius_m)`, clamped. Closer = higher.
- **Reciprocal:** `min(match_score, 20) / 20`. More reciprocal sticker matches = higher.
- **Activity:** `exp(-ln(2) × hours_since_update / 24)`. 24h half-life exponential decay using `user_locations.updated_at`. Recent = higher.

**Cache:** 60s in-memory TTL per user (`sync.RWMutex`). Background cleanup every 30s. `X-Cache: HIT|MISS` response header.

**Data flow:**
1. Go sets `request.jwt.claim.sub` via `set_config` in a pgx transaction for `auth.uid()`
2. Calls `find_nearby_traders(lat, lng, radius)` RPC → nearby traders + distance + `location_updated_at`
3. Calls `get_reciprocal_matches(nearby_ids)` RPC → reciprocal sticker overlap
4. Normalizes sub-scores, computes weighted total, sorts descending → returns JSON array

**Key files:**
- `go_service/internal/matchmaking/scorer.go` — `Scorer` interface, `DBScorer`, normalization functions (`NormalizeProximity`, `NormalizeReciprocal`, `NormalizeActivity`, `ComputeScore`)
- `go_service/internal/matchmaking/cache.go` — TTL cache with `sync.RWMutex`, background cleanup
- `go_service/internal/api/matchmaking.go` — `MatchmakingHandler` with `ListMatches` HTTP handler

## WebSocket Connection Manager

**Endpoint:** `GET /api/v1/ws` — upgrades to WebSocket. Requires JWT auth + age 13+. No attestation (connection pipe only).

**Connection limit:** 1 per user. New connection evicts existing with `StatusPolicyViolation`.

**Heartbeat:** Server pings every 30s, 10s pong timeout. Failed heartbeat closes the connection.

**Graceful shutdown:** Manager sends `StatusGoingAway` close frames to all connections, waits up to 5s for cleanup, then abandons. Runs before HTTP server shutdown.

**Architecture:** Goroutine-per-connection. `Conn.Run(ctx)` manages heartbeat loop + read pump. `Manager` is a `sync.RWMutex`-guarded `map[string]*Conn` registry. Non-blocking `Close()` via buffered channel signal (avoids blocking `nhooyr.io/websocket`'s 5s close handshake in hot paths).

**Middleware chain:** `RateLimit(30/min) → ValidateJWT → RequireAge13Plus`

**HTTP server:** `WriteTimeout` set to 0 to support long-lived WebSocket connections (REST writes complete quickly; WS writes use per-op `Config.WriteTimeout`).

**Key files:**
- `go_service/internal/ws/config.go` — `Config` struct, `DefaultConfig()` (30s heartbeat, 10s pong timeout, 4KB read limit)
- `go_service/internal/ws/conn.go` — `Conn` type, `Run()` lifecycle, heartbeat loop, read pump, `MessageHandler` callback
- `go_service/internal/ws/manager.go` — `Manager` registry, `Add`/`Get`/`Len`/`Shutdown`, pointer-safe eviction
- `go_service/internal/ws/handler.go` — `Handler` with `Upgrade` HTTP handler, server lifetime context

## Database Schema (Supabase)

**Existing tables:**
- `user_locations` — PostGIS geography points with GiST index, RLS own-row write, reads via SECURITY DEFINER RPCs only (no direct SELECT policy): `find_nearby_users()` for general proximity, `find_nearby_traders()` for trader discovery
- `stickers` — 980-sticker catalog (48 teams, 112 pages)
- `user_profiles` — Trust Score, age verification (`date_of_birth`, `is_under_13`, `age_verified_at` — immutable after verification), preferences
- `user_inventory` — User's sticker collection (OWNED/NEEDED/DUPLICATE status, quantity, RLS own-only)
- `trade_audit_log` — Immutable trade history (append-only via `record_trade()` SECURITY DEFINER function, RLS read-only for participants)
- `parental_consent_tokens` — Single-use, time-limited consent tokens (64-char hex, 7-day expiry, `consumed_at` null-until-used). RLS read-only for user's own tokens; writes via SECURITY DEFINER RPCs only.
- `guest_migrations` — Tracks completed guest-to-member inventory migrations (device_uuid, user_id, items_sent, items_written). UNIQUE on (device_uuid, user_id) for migration-level idempotency. RLS read-only for user's own rows; writes via SECURITY DEFINER RPC only.

**Planned tables (from PRD):**
- `matches` — Matchmaking results
- `messages` — Chat message persistence

All tables require RLS policies. The `trade_audit_log` is append-only. Migration `0007` includes a runtime audit that **fails the migration** if any public table lacks RLS. Migration `0009` adds `verify_age()` SECURITY DEFINER RPC and immutability trigger for age fields. Migration `0010` adds parental consent token management RPCs and extends the immutability trigger to protect consent fields. Migration `0011` adds `guest_migrations` table and `migrate_guest_inventory()` RPC for idempotent guest-to-member inventory transfer. Migration `0012` replaces the broad `user_locations` SELECT policy with `find_nearby_users()` SECURITY DEFINER RPC (50 km max radius, excludes under-13, excludes caller). Migration `0013` adds `find_nearby_traders()` SECURITY DEFINER RPC — returns top 50 nearby users who have DUPLICATE stickers, ordered by `<->` KNN distance; includes `display_name`, `duplicate_count`, `needed_count`. Migration `0014` adds `get_reciprocal_matches(p_nearby_ids uuid[])` SECURITY DEFINER RPC — given nearby user IDs from `find_nearby_traders()`, returns reciprocal matches by intersecting DUPLICATE/NEEDED inventories. Returns `user_id`, `they_have_i_need`, `i_have_they_need`, `match_score` (LEAST of the two counts). Array clamped to 50. Authenticated only. Migration `0015` modifies `find_nearby_traders()` to also return `location_updated_at` (from `user_locations.updated_at`) as an activity signal for the Go matchmaking scoring engine. Full policy matrix: [`docs/rls-policies.md`](docs/rls-policies.md).

**Supabase Edge Functions:**
- `send-consent-email` — Authenticated POST. Sends parental consent email (Resend API in prod, console log in dev). Called from Flutter after `request_parental_consent()` RPC.
- `confirm-consent` — Public GET. Web page served when parent clicks email link. Calls `confirm_parental_consent()` RPC via `service_role`. Returns branded HTML (success/error/expired).
- `migrate-guest-inventory` — Authenticated POST. Receives device_uuid + inventory items array, validates, then calls `migrate_guest_inventory()` RPC to upsert items into cloud inventory. Idempotent (duplicate device+user migrations return previous result). Called from Flutter during post-signup onboarding.

## Target Market & Compliance

**Primary market: El Salvador.** COPPA (U.S.) and GDPR (EU) do not apply unless the app expands to those regions. Local law: LEPINA (Ley de Protección Integral de la Niñez y Adolescencia).

### Age-Appropriate Safeguards (kept as good practice)

- Under-13 users (`is_under_13` flag in Supabase user metadata):
  - Blocked from chat (Go middleware returns 403 + Flutter screen-level guard)
  - Location features disabled
  - Wishlist-only mode (no real-time trading)
  - **Flutter enforcement:** Screen-level guards via `isUnder13Provider` on `MatchesScreen`, `MatchScreen`, and `ChatScreen`. Each renders a `SwappRestrictedEmptyState` (reusable widget in `shared/widgets/`) instead of functional UI. ChatScreen also skips Ably WebSocket initialization for under-13 users.
- Age verification at sign-up
- Guest mode uses encrypted local storage (no server PII). On signup, local inventory is migrated via `migrate-guest-inventory` Edge Function (idempotent, no data loss).

> **Future expansion note:** If the app launches in the U.S. or EU, COPPA/GDPR compliance (verifiable parental consent, data export/erasure, per-country DPA) must be added before entering those markets.

## Environment Variables

```
SUPABASE_URL              # Supabase project URL
SUPABASE_ANON_KEY         # Public anon key (safe for client)
SUPABASE_SERVICE_ROLE_KEY # Server-only, bypasses RLS
SUPABASE_DB_URL           # PostgreSQL connection string
ABLY_API_KEY              # Ably API key (server-only)
ONESIGNAL_APP_ID          # OneSignal app ID (passed via --dart-define)
GOOGLE_WEB_CLIENT_ID      # Google OAuth Web Client ID (--dart-define + Supabase provider)
GOOGLE_IOS_CLIENT_ID      # Google iOS Client ID from GoogleService-Info.plist (--dart-define)
RESEND_API_KEY            # Resend API key for transactional emails (Edge Functions, production only)
SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID   # config.toml local dev
SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET      # config.toml local dev
SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID    # config.toml local dev
SUPABASE_AUTH_EXTERNAL_APPLE_SECRET       # config.toml local dev
GOOGLE_CLOUD_PROJECT_NUMBER               # Play Integrity token verification (Go .env + --dart-define)
APPLE_APP_ID                              # App Attest verification, format: TEAMID.BUNDLEID (Go .env)
ATTESTATION_DISABLED                      # Set to "true" to bypass attestation in dev (Go .env)
```

Deployment secrets (GitHub Actions): `APPSTORE_CONNECT_*`, `PLAY_SERVICE_ACCOUNT_JSON`, `ANDROID_KEYSTORE*`, `IOS_CERTIFICATE*`, `PROVISIONING_PROFILE`, `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`.

## CI/CD Pipeline

GitHub Actions on PRs and pushes to `main`:
1. **lint-test** — `flutter analyze` + `flutter test`
2. **build-android** — AAB → Google Play internal track (on push to main)
3. **build-ios** — IPA → TestFlight (on push to main)

Version auto-bumps: `1.0.${{ github.run_number }}`. Flutter version pinned in `.flutter-version`.

## MVP Phases & Current Status

| Phase | Scope | Weeks | Status |
|-------|-------|-------|--------|
| Phase 0: Setup | Repo, CI/CD, Supabase, Ably, scaffolds | W0 | Partially done (tasks 1-4 complete) |
| Phase 1: Track + Safeguards | 980-sticker catalog, auth, age gate | W1-W5 | In progress (auth + age verification gate + sticker catalog screen done) |
| Phase 2: Discover | PostGIS proximity, Go matchmaking, swipe UI | W6-W9 | Not started |
| Phase 3: Trade | Ably chat, inventory locking, atomic trades | W10-W13 | Not started |
| Pre-Launch | Store submissions, scaling, monitoring | W14-W15 | Not started |

**71 total tasks, 35 critical, ~160 estimated days across 15 weeks.**

### Critical Path Milestones
1. Age safeguards implemented — W5
2. Go matchmaking engine deployed — W8
3. Trade execution stored procedure — W11
4. Load test pass — W13
5. App Store approval — W15 (before June 11 kickoff)

## Key Non-Functional Requirements

- 120 FPS scroll performance
- <50ms inventory locks
- 50K concurrent users at peak
- 99.9% uptime
- <200ms image load (sticker thumbnails)
- <100ms p95 spatial queries
- 0 double-trades (pessimistic locking + advisory locks + idempotency)

## Security

- Certificate pinning on all API calls (see Certificate Pinning section below)
- App attestation — Play Integrity (Android) + App Attest (iOS) (see App Attestation section below)
- Root/jailbreak detection with reduced trade limits (see Root/Jailbreak Detection section below)
- Replay prevention (nonces)
- RLS on all Supabase tables
- OWASP Mobile Top 10 compliance
- Trade idempotency keys to prevent replay attacks
- Saga pattern with state machine for trade execution

## Certificate Pinning

**Method:** SPKI SHA-256 public key pinning (survives cert renewal if key pair stays the same).

**Two layers:**
1. **Dart layer (primary):** `PinnedHttpClient` wraps the `http.Client` passed to `Supabase.initialize()`. Before each request to a pinned domain, `CertificatePinner` opens a `SecureSocket`, extracts the leaf certificate's SubjectPublicKeyInfo via ASN.1 DER parsing (`asn1lib`), SHA-256 hashes it, and compares against pinned base64 hashes. Results are cached with a 5-minute TTL. Non-pinned domains pass through unchanged.
2. **Android native (defense-in-depth):** `network_security_config.xml` with `<pin-set>` entries. Covers native HTTP traffic (e.g., Google Sign-In plugin) that bypasses Dart's BoringSSL stack.

**Pinned domains:**
- `hieuxypdjrdweznedjsm.supabase.co` — leaf + intermediate CA (Google Trust Services WE1)
- Go backend (`api.stickerstadium.app`) — placeholder, add hashes when deployed

**Key files:**
- `flutter_app/lib/core/services/certificate_pinner.dart` — `CertificatePins` (pin store), `CertificatePinner` (validation + SPKI extraction), `CertificatePinningException`
- `flutter_app/lib/core/services/pinned_http_client.dart` — `PinnedHttpClient extends http.BaseClient`
- `flutter_app/android/app/src/main/res/xml/network_security_config.xml` — Android pin declarations
- `flutter_app/lib/main.dart` — wires `AttestedHttpClient` → `DeviceIntegrityHttpClient` → `PinnedHttpClient` into `Supabase.initialize(httpClient:)`, skipped on web (`kIsWeb`)

**Updating pins:** Extract SPKI hash with:
```bash
openssl s_client -connect DOMAIN:443 -servername DOMAIN </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | base64
```
Update the hash sets in `CertificatePins.pins` (Dart) and `network_security_config.xml` (Android). Each domain should have at least 2 pins (leaf + backup/intermediate) to avoid lockout on cert rotation.

## App Attestation

**Method:** Play Integrity API (Android) + App Attest (iOS) — rejects requests from tampered, emulated, or non-genuine clients.

**Flow:**
```
Flutter client
  1. Generate platform attestation token via AttestationService
  2. Attach X-Attestation-Token + X-Attestation-Platform headers
  3. Send request with JWT + attestation headers

Go backend (VerifyAttestation middleware)
  1. Extract X-Attestation-Token and X-Attestation-Platform headers
  2. Android: decode + verify Play Integrity token via Google API
  3. iOS: verify App Attest assertion (CBOR decode, Apple cert chain)
  4. Reject 403 ATTESTATION_FAILED if invalid
```

**Middleware chain order:** `RateLimit → VerifyAttestation → ValidateJWT → ReadDeviceIntegrity → RequireAge13Plus`

**Flutter HTTP client chain:** `AttestedHttpClient → DeviceIntegrityHttpClient → PinnedHttpClient → http.Client()`

**Android verification:** Go calls Google's `playintegrity.googleapis.com/v1/{projectNumber}:decodeIntegrityToken` endpoint. Requires `appRecognitionVerdict == "PLAY_RECOGNIZED"` and `deviceRecognitionVerdict` containing `"MEETS_DEVICE_INTEGRITY"`.

**iOS verification:** CBOR-decodes the App Attest assertion, validates the x5c certificate chain against Apple's App Attestation Root CA, and checks authenticator data length.

**Dev mode:** Set `ATTESTATION_DISABLED=true` in `.env` to bypass attestation during local development.

**Key files:**
- `flutter_app/lib/core/services/attestation_service.dart` — `AttestationService` wraps `app_device_integrity` plugin
- `flutter_app/lib/core/services/attested_http_client.dart` — `AttestedHttpClient extends http.BaseClient`, attaches headers
- `go_service/internal/attestation/attestation.go` — `Verifier` implements `IntegrityChecker` interface
- `go_service/internal/middleware/attestation.go` — `VerifyAttestation` middleware function

## Root/Jailbreak Detection

**Method:** Client-side detection via `safe_device` package (Android: su binary, Magisk, test-keys; iOS: Cydia, sandbox escape, writable system paths). This is an untrusted advisory signal — defense-in-depth alongside attestation.

**Client-side:** `DeviceIntegrityService` checks once at app launch and caches the result for the session lifetime. `DeviceIntegrityHttpClient` attaches `X-Device-Integrity: compromised|clean` header to all requests. Header omitted when detection is unavailable (web, exception).

**Server-side:** `ReadDeviceIntegrity` middleware reads the header and sets a `deviceCompromised` boolean in request context. Logs `slog.Warn` with user ID, IP, path, method for analytics when compromised. Never blocks — only sets context for downstream handlers.

**Trade limits** (via `TradeLimiter` middleware, applied to future trade endpoints):
- Normal devices: 20 trades/hour
- Compromised devices: 5 trades/hour

Returns 429 `TRADE_LIMIT_EXCEEDED` with `Retry-After` when exceeded.

**Key files:**
- `flutter_app/lib/core/services/device_integrity_service.dart` — `DeviceIntegrityService` with injectable check functions
- `flutter_app/lib/core/services/device_integrity_http_client.dart` — `DeviceIntegrityHttpClient extends http.BaseClient`
- `go_service/internal/middleware/device_integrity.go` — `ReadDeviceIntegrity` middleware
- `go_service/internal/middleware/trade_limiter.go` — `TradeLimiter` middleware with `TradeLimiterConfig`

## Design System

**Brand:** Bold & Sporty — FIFA World Cup 2026 inspired. Light + dark themes.

**Color palette:** Deep navy primary (`#0A1F44`), gold secondary (`#C89B3C`), pitch green tertiary (`#2E7D32`). Full `ColorScheme` with explicit light/dark constructors (not `fromSeed`).

**Typography:** Montserrat (headings, bold/geometric) + Inter (body/labels, legible). Via `google_fonts` package.

**Design tokens:** `SwappTokens` — spacing (2–48px), border radius (4–999px), elevation (0/1/3/6), button heights (36/44/52px).

**Reusable widgets** (import via `package:flutter_app/shared/shared.dart`):
- `SwappCard` — `SwappCardVariant.filled|elevated|outlined`, supports `onTap`, custom `padding`
- `SwappButton` — `SwappButtonVariant.primary|secondary|outlined`, `SwappButtonSize.small|medium|large`, `isLoading` state, optional `icon`
- `SwappProgressBar` — `current`/`total` with animated bar, optional `label`, `showPercentage`
- `SwappRestrictedEmptyState` — Centered empty state for feature-gated screens (`icon`, `title`, `subtitle`, optional `actionLabel`/`onAction`)

**Theme mode:** Controlled by `themeModeProvider` (Riverpod `NotifierProvider<ThemeModeNotifier, ThemeMode>`). Defaults to `ThemeMode.system`. Toggle via `ref.read(themeModeProvider.notifier).toggle()`.

## Coding Conventions

- **Flutter**: Feature-based folder structure under `features/`. Data layer (`data/services/`) separated from presentation (`presentation/screens/`). Use Riverpod providers; avoid raw StatefulWidgets where possible.
- **Go**: Standard `cmd/` + `internal/` layout. All packages under `internal/` are private. Use Chi middleware chain. Context-based dependency passing. Structured JSON responses.
- **SQL**: Migrations in `supabase/migrations/` with sequential numbering (`0001_`, `0002_`, ...). Always add RLS policies. Use `timestamptz` for all timestamps.

## Infrastructure Budget

- **Development**: ~$25/mo (Supabase Pro)
- **Tournament peak**: $930–$1,760/mo (Supabase Team + Ably Pro + Cloud Run + Upstash Redis + OneSignal)
