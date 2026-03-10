# World Cup 2026 Sticker Swap App

Monorepo for a mobile sticker trading platform built around the FIFA World Cup 2026 Panini album.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile | Flutter (iOS + Android) |
| Backend | Go HTTP service |
| Database | Supabase (PostgreSQL + PostGIS) |
| Real-time | Ably (WebSocket chat & presence) |
| CI/CD | GitHub Actions → TestFlight / Google Play |

## Project Structure

```
flutter_app/   → Mobile client (screens, Ably service, chat)
go_service/    → Token auth, matchmaking, trading engine
supabase/      → Migrations, edge functions, config
```

## Prerequisites

- Flutter SDK (version pinned in `.flutter-version`)
- Go 1.21+
- Supabase CLI
- Copy `.env.example` → `.env` and fill in credentials

## Local Development

```bash
make dev       # Run Go service on :8080
make test      # Run Go tests
make migrate   # Reset Supabase local database
```

## Architecture

**Auth flow:** Flutter → Supabase Auth (JWT) → Go service validates JWT → signs scoped Ably token → Flutter connects to Ably WebSocket.

**Real-time channels:**
- `match:{matchId}` — trade chat between matched users
- `user:{userId}:notifications` — personal alerts (subscribe-only)

**Key policies:**
- Age gating — under-13 users are blocked from chat (PRD §7.3)
- Rate limiting — 120 req/min (authenticated), 30 req/min (guest)
- PostGIS proximity queries for local match discovery

## CI/CD

GitHub Actions workflow (`.github/workflows/mobile-ci.yml`) runs on PRs and pushes to `main`:

1. **lint-test** — `flutter analyze` + `flutter test`
2. **build-android** — builds AAB, deploys to Google Play internal track on `main`
3. **build-ios** — builds IPA, uploads to TestFlight on `main`

### Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `APPSTORE_CONNECT_API_KEY` | Apple API key for TestFlight uploads |
| `APPSTORE_CONNECT_API_KEY_ID` | Apple API key ID |
| `APPSTORE_CONNECT_ISSUER_ID` | Apple team/issuer ID |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Play service account |
| `ANDROID_KEYSTORE` | Android signing keystore (base64) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Signing key alias |
| `ANDROID_KEY_PASSWORD` | Signing key password |
| `IOS_CERTIFICATE` | iOS signing certificate (base64) |
| `IOS_CERTIFICATE_PASSWORD` | Certificate password |
| `PROVISIONING_PROFILE` | iOS provisioning profile (base64) |