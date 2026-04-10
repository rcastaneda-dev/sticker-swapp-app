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
│   │   ├── core/          # App-wide: router, services, providers
│   │   │   ├── providers/
│   │   │   │   └── push_notification_providers.dart  # OneSignal lifecycle + user association
│   │   │   └── services/
│   │   │       ├── attestation_service.dart          # Play Integrity / App Attest tokens
│   │   │       ├── attested_http_client.dart         # http.BaseClient with attestation headers
│   │   │       ├── certificate_pinner.dart           # SPKI SHA-256 pin validation
│   │   │       ├── device_integrity_service.dart     # Root/jailbreak detection (safe_device)
│   │   │       ├── device_integrity_http_client.dart # http.BaseClient with X-Device-Integrity header
│   │   │       ├── location_service.dart              # Foreground GPS + user_locations upsert
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
│   │   │   │   │   ├── services/user_inventory_service.dart
│   │   │   │   │   ├── providers/sticker_providers.dart
│   │   │   │   │   ├── providers/guest_inventory_providers.dart
│   │   │   │   │   ├── providers/user_inventory_providers.dart
│   │   │   │   │   ├── providers/effective_inventory_providers.dart
│   │   │   │   │   ├── providers/collection_progress_providers.dart
│   │   │   │   │   └── providers/wishlist_providers.dart
│   │   │   │   ├── presentation/screens/sticker_catalog_screen.dart
│   │   │   │   ├── presentation/screens/collection_progress_screen.dart
│   │   │   │   └── stickers.dart          # Barrel export
│   │   │   ├── chat/
│   │   │   │   ├── data/services/
│   │   │   │   └── presentation/screens/
│   │   │   └── matching/
│   │   │       ├── data/
│   │   │       │   └── providers/
│   │   │       │       └── location_providers.dart  # Location permission & update state
│   │   │       └── presentation/
│   │   │           ├── screens/
│   │   │           │   ├── matches_screen.dart     # Main hub (under-13 → wishlist)
│   │   │           │   └── match_screen.dart       # Trade match (under-13 guard)
│   │   │           └── widgets/
│   │   │               └── under13_wishlist_view.dart  # Wishlist for under-13 users
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
│       ├── ably/          # Token generation (HMAC-signed) + REST SDK publisher
│       ├── attestation/   # Play Integrity + App Attest verification
│       ├── middleware/    # Auth, age gating, rate limiting, attestation, device integrity, trade limiting
│       ├── db/            # pgx connection pool
│       ├── auth/          # (reserved)
│       ├── matches/       # Swipe & match creation (MatchCreator, ParticipantChecker interfaces)
│       ├── matchmaking/   # Scoring engine, in-memory cache
│       ├── onesignal/     # Push notification sending (OneSignal REST API)
│       ├── ws/            # WebSocket connection manager (goroutine-per-connection)
│       └── trades/        # Inventory locking + trade execution (InventoryLocker, TradeExecutor interfaces)
├── supabase/              # Migrations & Edge Functions
│   ├── migrations/
│   └── functions/
├── .github/workflows/     # CI/CD pipelines
├── cloud-run-service.yaml # Declarative Cloud Run config (Knative)
├── Makefile
└── .env
```

## Quick Commands

```bash
make dev          # Run Go service on :8080 (sources .env automatically)
make test         # Run Go tests
make migrate      # Reset local Supabase DB (supabase db reset)
make build        # Build Go binary locally (output: bin/server)
make docker-build # Build Docker image
make docker-run   # Run Docker image with local .env
```

Flutter:
```bash
cd flutter_app && flutter analyze   # Lint
cd flutter_app && flutter test      # Widget tests
cd flutter_app && flutter run \     # Run app (requires --dart-define for auth)
  --dart-define=SUPABASE_URL=https://hieuxypdjrdweznedjsm.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-key> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id> \
  --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id> \
  --dart-define=GO_SERVICE_URL=http://localhost:8080
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

**Real-time updates:** All widgets watch `effectiveInventoryProvider` (which delegates to `guestInventoryProvider` for guests or `userInventoryProvider` for authenticated users) — toggling a sticker in the catalog immediately updates progress bars and counts on the progress screen.

## User Inventory (Authenticated)

**Service:** `UserInventoryService` reads/writes the authenticated user's sticker inventory from the Supabase `user_inventory` table. Follows `StickerService` pattern (injectable `SupabaseClient`, lazy resolution to avoid `Supabase.instance` in test fakes).

**Methods:**
- `fetchOwnedStickerIds()` → `Set<int>` (sticker_ids where status IN OWNED, DUPLICATE)
- `toggleSticker(int stickerId)` → check existing row: if exists → delete, if not → insert as OWNED
- `createWishlistShare()` → calls `create_wishlist_share` RPC, returns token string

**Providers:**
- `userInventoryServiceProvider` — Provider<UserInventoryService> singleton
- `userInventoryProvider` — AsyncNotifierProvider<UserInventoryNotifier, Set<int>>. Same interface as `GuestInventoryNotifier`. Optimistic updates with rollback on error.

**Effective inventory switching layer** (`effective_inventory_providers.dart`):
- `effectiveInventoryProvider` — `Provider<AsyncValue<Set<int>>>`: watches `authStateProvider`, returns `userInventoryProvider` when authenticated, `guestInventoryProvider` when guest
- `toggleEffectiveSticker(WidgetRef ref, int stickerId)` — top-level helper that delegates to the correct notifier based on auth state

**Key files:**
- `flutter_app/lib/features/stickers/data/services/user_inventory_service.dart` — Service with lazy SupabaseClient
- `flutter_app/lib/features/stickers/data/providers/user_inventory_providers.dart` — Riverpod providers
- `flutter_app/lib/features/stickers/data/providers/effective_inventory_providers.dart` — Auth-aware switching layer

## Under-13 Wishlist

**Route:** `/matches` (under-13 branch) — replaces the `SwappRestrictedEmptyState` dead-end with a useful wishlist view showing stickers the user still needs, plus a shareable URL for parents/friends to help find stickers offline.

**Layout (`Under13WishlistView`):**
1. Header `SwappCard(elevated)`: "My Wishlist" title, "{count} stickers needed" subtitle, `SwappProgressBar` (owned/total), share button
2. Sticker count label
3. `SliverGrid` of needed stickers — image at 40% opacity, sticker number, team label. Responsive column count (3–6).
4. Empty state: "Collection complete!" with trophy icon when all stickers owned

**Share flow:** Tap "Share Wishlist" → `WishlistShareNotifier.generateShareLink()` → `UserInventoryService.createWishlistShare()` RPC → constructs full URL (`SUPABASE_URL/functions/v1/share-wishlist?token=...`) → copies to clipboard via `Clipboard.setData()` → SnackBar confirmation. Error state shows retry SnackBar.

**Providers** (`wishlist_providers.dart`):
- `wishlistProvider` — `Provider<List<Sticker>>`: all stickers minus owned (derives from `allStickersProvider` − `effectiveInventoryProvider`)
- `wishlistCountProvider` — `Provider<int>`: count of needed stickers
- `wishlistShareProvider` — `NotifierProvider<WishlistShareNotifier, WishlistShareState>`: state machine (idle → loading → success with URL / error). `WishlistShareStatus` enum: `idle`, `loading`, `success`, `error`.

**Database (migration `0017`):**
- `wishlist_shares` table: `id`, `token` (64-char hex, unique), `user_id` (FK), `display_name` (snapshot), `expires_at` (30 days), `created_at`. RLS: authenticated read own rows only.
- `create_wishlist_share()` RPC: SECURITY DEFINER. Reuses existing non-expired token. Generates 32-byte random hex token. Snapshots display_name. Returns `{success, token, already_exists}`. Granted to `authenticated` only.
- `get_shared_wishlist(p_token text)` RPC: SECURITY DEFINER. Validates token + expiry. Returns all stickers NOT in user's OWNED/DUPLICATE inventory. Granted to `service_role` only (called by Edge Function).

**Edge Function (`share-wishlist`):** Public GET endpoint. Query param: `?token=<hex>`. Calls `get_shared_wishlist(token)` via service_role client. Renders branded HTML page with stickers grouped by team (responsive CSS grid, Montserrat+Inter fonts, navy/gold/green palette). Error states for invalid/expired tokens.

**Key files:**
- `flutter_app/lib/features/stickers/data/providers/wishlist_providers.dart` — Wishlist derivation + share state machine
- `flutter_app/lib/features/matching/presentation/widgets/under13_wishlist_view.dart` — Wishlist UI widget
- `supabase/migrations/0017_add_wishlist_shares.sql` — Table + RPCs
- `supabase/functions/share-wishlist/index.ts` — Public HTML endpoint

## Location Service

**Scope:** Foreground-only GPS location permission and `user_locations` table upsert. Required for the matchmaking discovery feature (`GET /api/v1/matches`). Under-13 users are completely blocked at the provider layer.

**Package:** `geolocator` (handles both permission management and GPS position on iOS/Android).

**Platform config:**
- iOS: `NSLocationWhenInUseUsageDescription` in `Info.plist` (foreground only)
- Android: `ACCESS_FINE_LOCATION` in `AndroidManifest.xml` (no background permission)

**LocationService** (`core/services/location_service.dart`):
- All platform calls injectable via typedef callbacks for unit testing (follows `DeviceIntegrityService` pattern)
- `SupabaseClient` resolved lazily — permission-only tests don't need Supabase initialization
- `checkPermission()` — reads current status without requesting
- `requestPermission()` — checks `deniedForever` first (avoids no-op on iOS), then requests
- `openAppSettings()` / `openLocationSettings()` — recovery from `deniedForever` / `serviceDisabled`
- `updateLocation()` — gets GPS position, upserts `POINT(lng lat)` + `accuracy_m` to `user_locations` via RLS policies
- `deleteLocation()` — removes row for opt-out / under-13 cleanup
- `buildPointWkt(lng, lat)` — static helper for PostGIS WKT format (longitude first)

**Permission status enum:** `LocationPermissionStatus` — `granted`, `grantedAlways`, `denied`, `deniedForever`, `serviceDisabled`, `unsupported`

**Providers** (`features/matching/data/providers/location_providers.dart`):
- `locationServiceProvider` — LocationService singleton
- `locationEnabledProvider` — `Provider<bool>`: `true` only for authenticated, age-verified, 13+ users. Single gate for under-13 policy.
- `locationPermissionProvider` — `FutureProvider<LocationPermissionStatus?>`: re-checks on auth state change; `null` when disabled
- `hasLocationPermissionProvider` — `Provider<bool>`: derived from permission status
- `locationNotifierProvider` — `AsyncNotifierProvider<LocationNotifier, LocationUpdateResult?>`: drives full flow (request permission → fetch position → upsert). Returns permission status if blocked, `null` on success.

**Key files:**
- `flutter_app/lib/core/services/location_service.dart` — Service with injectable deps
- `flutter_app/lib/features/matching/data/providers/location_providers.dart` — Riverpod providers

## Swipe Discovery UI

**Route:** `/matches` — Tinder-style card stack for discovering nearby traders. Under-13 users see `SwappRestrictedEmptyState` instead.

**Flow:** On screen load → request location permission → fetch GPS → `GET /api/v1/matches` (Go backend) → display scored match candidates as swipeable cards. Swipe right → `POST /api/v1/matches` (records swipe, creates mutual match if both swiped). Swipe left → skip (no API call).

**Card stack animation:** `GestureDetector` pan tracking + `AnimationController` with `AlignmentTween`. Swipe threshold: 30% of half-screen-width or 800px/s fling velocity. `RepaintBoundary` on every card, behind cards use GPU-composited `Matrix4` transforms. "TRADE" (green) / "SKIP" (red) stamp labels appear with opacity tied to drag distance.

**Match celebration:** On mutual match (201 response), a `MatchCelebrationOverlay` renders with elastic scale-in animation. Two CTAs: "Open Chat" → `/matches/{matchId}`, "Keep Swiping" → dismiss.

**Match notification (in-app):** When the user dismisses the celebration overlay via "Keep Swiping", the match is tracked in `matchNotificationProvider` (in-memory `List<UnviewedMatch>`). A floating SnackBar toast shows "Matched with {name}!" with a "View" action navigating to `/matches/{matchId}`. An AppBar badge icon (`Icons.chat_bubble_outline` with `Badge` count) appears on the discovery screen — tapping it navigates to the most recent unviewed match. Viewing any match detail screen (`MatchScreen`) automatically marks that match as viewed (badge count decrements). Badge is hidden for under-13 users.

**Dart-define:** `GO_SERVICE_URL` — base URL for the Go matchmaking backend (e.g., `http://localhost:8080` for local dev).

**Models:**
- `ScoredMatch` — maps `GET /api/v1/matches` JSON response (user_id, display_name, distance_m, they_have_i_need, i_have_they_need, total_score, etc.)
- `SwipeResult` — maps `POST /api/v1/matches` JSON response (matched, match_id, status)

**Providers:**
- `matchDiscoveryServiceProvider` — `Provider<MatchDiscoveryService>` singleton
- `discoveryProvider` — `NotifierProvider<DiscoveryNotifier, DiscoveryState>` — state machine (awaitingLocation → loading → ready/empty/error), card index management, swipe actions
- `matchNotificationProvider` — `NotifierProvider<MatchNotificationNotifier, List<UnviewedMatch>>` — in-memory unviewed match tracking (addMatch, markViewed, clear)
- `unviewedMatchCountProvider` — `Provider<int>` — derived badge count
- `mostRecentUnviewedMatchProvider` — `Provider<UnviewedMatch?>` — most recent unviewed match for badge tap navigation

**Key files:**
- `flutter_app/lib/features/matching/data/models/scored_match.dart` — ScoredMatch model
- `flutter_app/lib/features/matching/data/models/swipe_result.dart` — SwipeResult model
- `flutter_app/lib/features/matching/data/services/match_discovery_service.dart` — HTTP service
- `flutter_app/lib/features/matching/data/providers/discovery_providers.dart` — Discovery state
- `flutter_app/lib/features/matching/data/providers/match_notification_providers.dart` — Match notification state
- `flutter_app/lib/features/matching/presentation/widgets/swipe_card_stack.dart` — Card stack animation
- `flutter_app/lib/features/matching/presentation/widgets/trader_card.dart` — Card content
- `flutter_app/lib/features/matching/presentation/widgets/match_celebration_overlay.dart` — Mutual match overlay
- `flutter_app/lib/features/matching/presentation/screens/matches_screen.dart` — Screen integrating all above

## Push Notifications

**Method:** OneSignal + FCM (Android) / APNs (iOS). Server-side push via OneSignal REST API when a mutual match is created. Under-13 users are excluded at multiple layers.

**Flow:**
```
User B swipes right → POST /api/v1/matches → mutual match (201)
  Go handler:
    1. Return 201 Created to User B (in-app celebration overlay)
    2. Async goroutine: look up User B's display name → send OneSignal push to User A
  User A (backgrounded):
    1. Receives OS push: "Carlos wants to trade with you!"
    2. Taps notification → Flutter click handler → GoRouter.push('/matches/{matchId}')
  User A (foregrounded):
    1. Foreground handler suppresses OS notification
    2. Adds match to matchNotificationProvider → badge + toast
```

**Notification payload:** `{headings: "New Match!", contents: "{name} wants to trade!", data: {match_id, type: "match_created"}}`

**OneSignal user association lifecycle:** Managed by `pushNotificationLifecycleProvider` in `app.dart`. Watches `authStateProvider` + `isUnder13Provider`:
- Authenticated + 13+ → `OneSignal.login(userId)` (associates device with external_id)
- Unauthenticated or under-13 → `OneSignal.logout()` (disassociates device)

**Under-13 enforcement (triple-layered):**
1. Flutter: `pushNotificationLifecycleProvider` never calls `OneSignal.login()` for under-13 → no external_id → cannot be targeted by push
2. Go middleware: `RequireAge13Plus()` blocks under-13 from `POST /api/v1/matches` → push-sending code unreachable
3. Both swipe participants passed the age gate to swipe, so notification recipients are always 13+

**Cold-start deep-link:** If a notification tap fires before the lifecycle provider is wired, the match ID is buffered in `_pendingMatchId` and processed when `processPendingNotification()` is called.

**Foreground suppression:** When the app is in the foreground, match notifications are suppressed at the OS level and routed through the in-app `matchNotificationProvider` (badge + toast) instead.

**Environment variables (Go):**
- `ONESIGNAL_APP_ID` — OneSignal App ID (same as Flutter dart-define)
- `ONESIGNAL_REST_API_KEY` — OneSignal REST API Key (server-only, never in client)
- If either is missing, `NoopNotifier` is used (push silently disabled)

**Providers:**
- `pushNotificationServiceProvider` — `Provider<PushNotificationService>` singleton (overridden in main() with initialized instance)
- `pushNotificationLifecycleProvider` — `Provider<void>` — manages OneSignal login/logout + notification tap/foreground handlers

**Key files:**
- `flutter_app/lib/core/services/push_notification_service.dart` — Service with injectable callbacks, click/foreground handlers, pending buffer
- `flutter_app/lib/core/providers/push_notification_providers.dart` — Riverpod lifecycle + service providers
- `go_service/internal/onesignal/notifier.go` — `Notifier` interface, `PushNotifier` (HTTP), `NoopNotifier` (dev)
- `go_service/internal/api/matches.go` — `MatchHandler` with async push on mutual match
- `go_service/internal/api/display_name.go` — `DisplayNameLookup` interface + DB implementation

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

## Ably SDK Integration (Go Service)

**SDK:** `github.com/ably/ably-go v1.3.0` — REST client for server-side channel publish. Import aliased as `ablySDK` to avoid collision with `internal/ably` package.

**Publisher** (`internal/ably/publisher.go`): `Publisher` interface with `RESTPublisher` (Ably REST SDK) and `NoopPublisher` (dev/test). On mutual match creation, the Go service publishes a `match.created` system event to the `match:{matchId}` Ably channel. This establishes the channel and the first persisted message.

**Match participant validation** (`internal/matches/participant.go`): `ParticipantChecker` interface with `DBParticipantChecker`. When `POST /api/v1/ably/auth` includes a `matchId`, the token handler verifies the requesting user is `user1_id` or `user2_id` in the match before issuing a scoped token. Returns 403 `NOT_PARTICIPANT` if not in the match, 400 `INVALID_PARAMS` if matchId is not a valid UUID.

**Token scoping:** Each token is scoped to the specific match channel (`publish`, `subscribe`, `presence`, `history`) plus the user's personal notification channel (`subscribe` only). 1-hour TTL.

**Channel creation flow:**
```
POST /api/v1/matches → mutual match (201) → async goroutine:
  1. PublishMatchCreated(ctx, matchId, event) → Ably REST API → match:{matchId} channel created
  2. sendMatchPush(callerID, result) → OneSignal push to other user
```

**24h message history:** Configured via Ably Dashboard channel rule on `match:*` namespace with "Persist all messages" enabled. No code change needed — the Flutter Ably SDK retrieves history via `channel.history()`.

**Key files:**
- `go_service/internal/ably/publisher.go` — Publisher interface, RESTPublisher, NoopPublisher, MatchCreatedEvent
- `go_service/internal/ably/token_handler.go` — Token issuance with match participant validation
- `go_service/internal/matches/participant.go` — ParticipantChecker interface, DBParticipantChecker

## API Endpoints (Go Service)

| Method | Path                | Auth   | Attestation | Rate Limit | Description                    |
|--------|---------------------|--------|-------------|------------|--------------------------------|
| GET    | `/healthz`          | None   | None        | None       | DB connectivity check          |
| POST   | `/api/v1/ably/auth` | JWT    | Required    | 120/min    | Issue scoped Ably token        |
| GET    | `/api/v1/matches`   | JWT    | Required    | 120/min    | Scored match discovery         |
| POST   | `/api/v1/matches`   | JWT    | Required    | 120/min    | Create match (mutual swipe)    |
| POST   | `/api/v1/matches/{matchId}/lock` | JWT | Required | 120/min | Lock caller's DUPLICATE stickers for trade |
| DELETE | `/api/v1/matches/{matchId}/lock` | JWT | Required | 120/min | Release inventory locks (MANUAL_RELEASE) |
| POST   | `/api/v1/trades`    | JWT    | Required    | 120/min + TradeLimiter | Atomic trade execution |
| GET    | `/api/v1/ws`        | JWT    | None        | 30/min     | WebSocket upgrade (1 conn/user)|

Rate limits: 120 req/min (authenticated), 30 req/min (guest). Returns 429 with `Retry-After: 60`. Trade endpoint additionally uses `TradeLimiter` middleware (20/hour normal, 5/hour compromised devices).

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

## Match Creation (Swipe & Match)

**Endpoint:** `POST /api/v1/matches` — record a right-swipe; if mutual, create a PENDING match.

**Request body:** `{"target_user_id": "uuid"}`

**Response:**
- **201 Created** — mutual swipe, match created: `{matched: true, match_id, user1_id, user2_id, status: "PENDING", created_at}`
- **200 OK** — swipe recorded, no match yet: `{matched: false, swipe_recorded: true}`

**Validation:** Auth required, valid UUID, not self-swipe. Both users must have swiped right (enforced by `create_match_if_mutual()` RPC).

**Idempotency:** Duplicate swipes and duplicate match creation are safe — `ON CONFLICT DO NOTHING` on both `swipes` and `matches` tables. Concurrent mutual swipes handled via canonical ordering (`LEAST`/`GREATEST` user IDs) + fallback SELECT.

**Key files:**
- `go_service/internal/matches/matcher.go` — `MatchCreator` interface, `CreateMatchResult` type
- `go_service/internal/matches/db_matcher.go` — `DBMatchCreator` pgx implementation (tx + set_config + RPC)
- `go_service/internal/api/matches.go` — `MatchHandler` with `CreateMatch` HTTP handler

## Inventory Soft-Locks

**Purpose:** Prevent the same DUPLICATE stickers from being offered in multiple concurrent trades. When a user opens a match chat, their DUPLICATE stickers are soft-locked for that match.

**Endpoints:**
- `POST /api/v1/matches/{matchId}/lock` — Lock caller's DUPLICATE stickers for this match (15-min TTL). Extends existing lock if already active.
- `DELETE /api/v1/matches/{matchId}/lock` — Release locks with `MANUAL_RELEASE` reason.

**Lock lifecycle:**
1. User opens match screen → `POST .../lock` → advisory lock on match → `SELECT FOR UPDATE` on inventory → check conflicts with other active locks → insert `inventory_locks` row
2. Re-opening chat before expiry → extends `expires_at` by 15 min
3. Trade completes → Go service calls `release_inventory_locks(matchId, 'TRADE_COMPLETED')` (service_role)
4. User leaves → `DELETE .../lock` → `release_inventory_locks(matchId, 'MANUAL_RELEASE')`
5. Timeout → passive expiry (`expires_at > now()` check in queries)

**Concurrency guarantees:**
- `pg_advisory_xact_lock(hashtext(match_id))` — serializes concurrent lock attempts on the same match
- `SELECT ... FOR UPDATE` on `user_inventory` rows — prevents concurrent inventory mutations during lock acquisition
- Conflict check — stickers locked in another active match are rejected (`STICKERS_ALREADY_LOCKED`)

**Response (POST lock):**
- `200 OK` — `{success: true, sticker_ids: [int], lock_count: int, expires_at: string, extended: bool}`
- `409 Conflict` — `{success: false, error: "STICKERS_ALREADY_LOCKED"|"NO_DUPLICATES"|"NOT_PARTICIPANT"|"MATCH_NOT_PENDING"|"MATCH_NOT_FOUND"}`

**Key files:**
- `supabase/migrations/0018_add_inventory_locks.sql` — Table + RPCs
- `go_service/internal/trades/locker.go` — `InventoryLocker` interface, `LockResult`, `ReleaseResult`
- `go_service/internal/trades/db_locker.go` — `DBInventoryLocker` pgx implementation
- `go_service/internal/api/trades.go` — `TradeHandler` with `LockInventory`, `ReleaseInventory`, and `Execute` handlers

## Trade Execution

**Endpoint:** `POST /api/v1/trades` — atomic trade execution. Requires JWT + attestation + age 13+ + `TradeLimiter`.

**Request body:** `{match_id, initiator_sticker_ids, responder_sticker_ids, idempotency_key}` — all fields required. `match_id` and `idempotency_key` must be valid UUIDs. Sticker arrays must be non-empty. The caller (from JWT) is the initiator.

**Atomic steps (single PostgreSQL transaction via `execute_trade()` SECURITY DEFINER RPC):**
1. Idempotency check — if `idempotency_key` already exists in `trade_audit_log`, return existing `trade_id` with `already_completed: true`
2. Validate match — exists, PENDING status, initiator is participant; derive responder
3. Advisory lock — `pg_advisory_xact_lock(hashtext(match_id))` serializes concurrent attempts
4. Verify active inventory locks — both initiator and responder must have active `inventory_locks` rows
5. Verify sticker subsets — offered sticker arrays must be contained in (`<@`) locked sticker arrays
6. Row-level lock — `SELECT FOR UPDATE` on affected `user_inventory` rows
7. Transfer stickers — for each sticker: sender's DUPLICATE quantity decremented (or downgraded to OWNED if quantity=1); recipient gets OWNED (or DUPLICATE+1 if already owned)
8. Audit — calls existing `record_trade()` with COMPLETED status
9. Update match — `SET status = 'COMPLETED'`
10. Release locks — calls existing `release_inventory_locks(match_id, 'TRADE_COMPLETED')`

**Response:**
- `200 OK` — `{success: true, trade_id, match_id, initiator_id, responder_id, initiator_sticker_ids, responder_sticker_ids, status: "COMPLETED"}` (also for idempotent replays with `already_completed: true`)
- `409 Conflict` — `{success: false, error: "MATCH_NOT_FOUND"|"NOT_PARTICIPANT"|"MATCH_NOT_PENDING"|"NO_ACTIVE_LOCK_INITIATOR"|"NO_ACTIVE_LOCK_RESPONDER"|"STICKERS_NOT_IN_LOCK"}`

**Concurrency guarantees:** Advisory lock on match + `SELECT FOR UPDATE` on inventory rows + idempotency key = zero double-trades.

**Key files:**
- `supabase/migrations/0019_execute_trade.sql` — `execute_trade()` SECURITY DEFINER RPC
- `go_service/internal/trades/executor.go` — `TradeExecutor` interface, `TradeRequest`, `TradeResult`
- `go_service/internal/trades/db_executor.go` — `DBTradeExecutor` pgx implementation
- `go_service/internal/api/trades.go` — `TradeHandler.Execute` HTTP handler

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
- `swipes` — Records individual right-swipes between users (swiper_id, target_id). UNIQUE (swiper_id, target_id) prevents duplicates and enables idempotent `ON CONFLICT DO NOTHING`. RLS read-only for own swipes; writes via SECURITY DEFINER RPC only.
- `matches` — Created when both users swipe right on each other. UUID primary key (used in Ably channel names). Canonical ordering (`CHECK user1_id < user2_id`) with UNIQUE constraint prevents duplicate A↔B matches. Status: `match_status` enum (PENDING/ACCEPTED/COMPLETED/CANCELLED/EXPIRED). RLS read-only for participants; writes via `create_match_if_mutual()` SECURITY DEFINER RPC.
- `wishlist_shares` — Shareable wishlist links for under-13 users (token, user_id, display_name snapshot, expires_at 30 days). Token: 64-char hex (32 random bytes). RLS: authenticated read own rows only. Writes via `create_wishlist_share()` SECURITY DEFINER RPC. Public lookup via `get_shared_wishlist(token)` (service_role only).
- `inventory_locks` — Soft-locks on user DUPLICATE stickers during trades. One row per user per match (`UNIQUE match_id, user_id`). Stores `sticker_ids int[]`, `expires_at` (15-min TTL), `released_at`/`release_reason` (NULL while active). Rows never deleted (table = audit trail). Active lock: `released_at IS NULL AND expires_at > now()`. Advisory lock on `hashtext(match_id)` serializes concurrent lock attempts. `SELECT FOR UPDATE` on `user_inventory` prevents concurrent inventory mutations during lock acquisition. RLS: participants read own match locks; writes via SECURITY DEFINER RPCs only. Migration `0018`.

**Planned tables (from PRD):**
- `messages` — Chat message persistence

All tables require RLS policies. The `trade_audit_log` is append-only. Migration `0007` includes a runtime audit that **fails the migration** if any public table lacks RLS. Migration `0009` adds `verify_age()` SECURITY DEFINER RPC and immutability trigger for age fields. Migration `0010` adds parental consent token management RPCs and extends the immutability trigger to protect consent fields. Migration `0011` adds `guest_migrations` table and `migrate_guest_inventory()` RPC for idempotent guest-to-member inventory transfer. Migration `0012` replaces the broad `user_locations` SELECT policy with `find_nearby_users()` SECURITY DEFINER RPC (50 km max radius, excludes under-13, excludes caller). Migration `0013` adds `find_nearby_traders()` SECURITY DEFINER RPC — returns top 50 nearby users who have DUPLICATE stickers, ordered by `<->` KNN distance; includes `display_name`, `duplicate_count`, `needed_count`. Migration `0014` adds `get_reciprocal_matches(p_nearby_ids uuid[])` SECURITY DEFINER RPC — given nearby user IDs from `find_nearby_traders()`, returns reciprocal matches by intersecting DUPLICATE/NEEDED inventories. Returns `user_id`, `they_have_i_need`, `i_have_they_need`, `match_score` (LEAST of the two counts). Array clamped to 50. Authenticated only. Migration `0015` modifies `find_nearby_traders()` to also return `location_updated_at` (from `user_locations.updated_at`) as an activity signal for the Go matchmaking scoring engine. Migration `0016` creates `swipes` table, `matches` table (with `match_status` enum), and `create_match_if_mutual(p_target_id uuid)` SECURITY DEFINER RPC — records a right-swipe, checks for mutual interest, and creates a PENDING match with canonical user ordering if both users have swiped. Idempotent via `ON CONFLICT DO NOTHING` on both tables. Granted to `authenticated` only. Migration `0017` creates `wishlist_shares` table, `create_wishlist_share()` RPC (authenticated, reuses non-expired tokens, generates 32-byte hex), and `get_shared_wishlist(p_token)` RPC (service_role only, returns needed stickers for shared wishlist page). Migration `0018` creates `inventory_locks` table with `lock_release_reason` enum (EXPIRED/TRADE_COMPLETED/TRADE_CANCELLED/MANUAL_RELEASE), `lock_inventory_for_trade(p_match_id)` RPC (authenticated, advisory lock + SELECT FOR UPDATE + conflict check, 15-min TTL, extends existing locks), and `release_inventory_locks(p_match_id, p_reason)` RPC (service_role only, releases all active locks for both participants). Full policy matrix: [`docs/rls-policies.md`](docs/rls-policies.md). Migration `0019` creates `execute_trade(p_match_id, p_initiator_id, p_initiator_sticker_ids, p_responder_sticker_ids, p_idempotency_key)` SECURITY DEFINER RPC (service_role only) — atomic trade execution: idempotency check → match validation → advisory lock → verify active inventory locks → verify sticker subsets → SELECT FOR UPDATE on inventory → transfer stickers (DUPLICATE→OWNED sender, OWNED/DUPLICATE upsert recipient) → call `record_trade()` → update match to COMPLETED → call `release_inventory_locks(TRADE_COMPLETED)`. Idempotent by `p_idempotency_key`.

**Supabase Edge Functions:**
- `send-consent-email` — Authenticated POST. Sends parental consent email (Resend API in prod, console log in dev). Called from Flutter after `request_parental_consent()` RPC.
- `confirm-consent` — Public GET. Web page served when parent clicks email link. Calls `confirm_parental_consent()` RPC via `service_role`. Returns branded HTML (success/error/expired).
- `migrate-guest-inventory` — Authenticated POST. Receives device_uuid + inventory items array, validates, then calls `migrate_guest_inventory()` RPC to upsert items into cloud inventory. Idempotent (duplicate device+user migrations return previous result). Called from Flutter during post-signup onboarding.
- `share-wishlist` — Public GET. Query param: `?token=<hex>`. Calls `get_shared_wishlist(token)` via service_role. Renders branded HTML page with needed stickers grouped by team (responsive CSS grid). Error states for invalid/expired tokens. Used by under-13 wishlist share flow.

## Target Market & Compliance

**Primary market: El Salvador.** COPPA (U.S.) and GDPR (EU) do not apply unless the app expands to those regions. Local law: LEPINA (Ley de Protección Integral de la Niñez y Adolescencia).

### Age-Appropriate Safeguards (kept as good practice)

- Under-13 users (`is_under_13` flag in Supabase user metadata):
  - Blocked from chat (Go middleware returns 403 + Flutter screen-level guard)
  - Location features disabled
  - Wishlist-only mode (no real-time trading) — `MatchesScreen` shows `Under13WishlistView` (needed stickers + shareable URL) instead of swipe discovery
  - **Flutter enforcement:** Screen-level guards via `isUnder13Provider` on `MatchesScreen`, `MatchScreen`, and `ChatScreen`. `MatchesScreen` renders `Under13WishlistView` for under-13 users. `MatchScreen` and `ChatScreen` render `SwappRestrictedEmptyState`. ChatScreen also skips Ably WebSocket initialization for under-13 users.
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
GO_SERVICE_URL                            # Go matchmaking backend URL (--dart-define, e.g. http://localhost:8080)
ONESIGNAL_REST_API_KEY                    # OneSignal REST API Key for server-side push (Go .env, never in client)
```

Deployment secrets (GitHub Actions): `APPSTORE_CONNECT_*`, `PLAY_SERVICE_ACCOUNT_JSON`, `ANDROID_KEYSTORE*`, `IOS_CERTIFICATE*`, `PROVISIONING_PROFILE`, `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`.

## CI/CD Pipeline

GitHub Actions workflows:

**Mobile** (`.github/workflows/mobile-ci.yml`) on PRs and pushes to `main`:
1. **lint-test** — `flutter analyze` + `flutter test`
2. **build-android** — AAB → Google Play internal track (on push to main)
3. **build-ios** — IPA → TestFlight (on push to main)

Version auto-bumps: `1.0.${{ github.run_number }}`. Flutter version pinned in `.flutter-version`.

**Go Service** (`.github/workflows/go-deploy.yml`) on pushes to `main` (when `go_service/**` changes):
1. **test** — `go test -race ./...`
2. **deploy** — Docker build → Artifact Registry → Cloud Run

## Go Service Deployment

**Target:** Google Cloud Run (us-central1)

**Image:** Multi-stage Docker build → `gcr.io/distroless/static-debian12:nonroot` (no shell, non-root, ~8MB)

**Auto-scaling:** 0–10 instances, 80 concurrent requests per instance, session affinity enabled.

**Request timeout:** 3600s (to support WebSocket connections). REST endpoints are protected by Go-level ReadTimeout (10s) and middleware rate limiting.

**Health probes:**
- Startup: `GET /healthz` — 5s intervals, 3 attempts, 3s timeout
- Liveness: `GET /healthz` — 30s intervals, 3 failures before restart, 3s timeout

**Secrets:** Injected from Google Secret Manager at runtime (not baked into image): `ABLY_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, `GOOGLE_CLOUD_PROJECT_NUMBER`, `APPLE_APP_ID`.

**CI/CD:** `.github/workflows/go-deploy.yml` — triggers on push to `main` when `go_service/**` changes. Uses Workload Identity Federation (no service account keys). Pushes to Artifact Registry, deploys via `google-github-actions/deploy-cloudrun`.

**Declarative config:** `cloud-run-service.yaml` — Knative service definition. Apply with `gcloud run services replace cloud-run-service.yaml` (replace `PROJECT_ID` placeholders first).

**Local Docker:**
```bash
make docker-build   # Build image
make docker-run     # Run with .env
```

**Key files:**
- `go_service/Dockerfile` — Multi-stage build (golang:1.26-alpine → distroless)
- `go_service/.dockerignore` — Build context exclusions
- `.github/workflows/go-deploy.yml` — CI/CD pipeline (test → build → deploy)
- `cloud-run-service.yaml` — Declarative Cloud Run service configuration

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
