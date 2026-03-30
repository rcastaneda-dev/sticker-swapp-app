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

**Guest mode:** Users can browse and track their 980-sticker collection locally without an account. Inventory is encrypted on-device via `flutter_secure_storage` (AES-256-GCM on native, localStorage on web). A first-launch flag ensures Keychain data does not persist after uninstall. On signup, local inventory migrates to the cloud.

**Key policies:**
- Certificate pinning — SPKI SHA-256 pins on Supabase and Go backend API calls (Dart-layer `PinnedHttpClient` + Android `network_security_config.xml`)
- App attestation — Play Integrity (Android) + App Attest (iOS) validated by Go middleware; rejects unverified clients with 403
- Root/jailbreak detection — client-side via `safe_device`, flagged to Go via `X-Device-Integrity` header; compromised devices get reduced trade limits (5/hour vs 20/hour)
- Age gating — under-13 users are blocked from chat (PRD §7.3)
- Rate limiting — 120 req/min (authenticated), 30 req/min (guest)
- PostGIS proximity queries for local match discovery

## CI/CD

### Mobile (`.github/workflows/mobile-ci.yml`)

Runs on PRs and pushes to `main`:

1. **lint-test** — `flutter analyze` + `flutter test`
2. **build-android** — builds AAB, deploys to Google Play internal track on `main`
3. **build-ios** — builds IPA, uploads to TestFlight on `main`

### Go Service (`.github/workflows/go-deploy.yml`)

Runs on pushes to `main` when `go_service/**` changes:

1. **test** — `go test -race ./...`
2. **deploy** — Docker build → Artifact Registry → Cloud Run (us-central1)

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
| `GOOGLE_CLOUD_PROJECT_NUMBER` | Play Integrity token verification |
| `APPLE_APP_ID` | App Attest verification (TEAMID.BUNDLEID) |
| `GCP_PROJECT_ID` | Google Cloud project ID |
| `WIF_PROVIDER` | Workload Identity Federation provider resource name |
| `WIF_SERVICE_ACCOUNT` | GCP service account email for Cloud Run deployments |

## Go Service Deployment (Cloud Run)

The Go backend deploys to Cloud Run with auto-scaling (0-10 instances).

| Setting | Value |
|---------|-------|
| Region | us-central1 |
| Min instances | 0 (scale to zero) |
| Max instances | 10 |
| Memory | 512Mi |
| CPU | 1 |
| Timeout | 3600s (WebSocket support) |
| Session affinity | Enabled |
| Concurrency | 80 req/instance |

### Infrastructure Setup (One-Time)

1. **Enable GCP APIs:** Cloud Run, Artifact Registry, Secret Manager, IAM Service Account Credentials

2. **Create Artifact Registry repo:**
   ```bash
   gcloud artifacts repositories create sticker-swap \
     --repository-format=docker \
     --location=us-central1
   ```

3. **Create service account:**
   ```bash
   gcloud iam service-accounts create sticker-swap-api \
     --display-name="Sticker Swap API"

   gcloud projects add-iam-policy-binding PROJECT_ID \
     --member="serviceAccount:sticker-swap-api@PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/secretmanager.secretAccessor"
   ```

4. **Store secrets in Secret Manager:**
   ```bash
   echo -n "value" | gcloud secrets create ABLY_API_KEY --data-file=-
   echo -n "value" | gcloud secrets create SUPABASE_URL --data-file=-
   echo -n "value" | gcloud secrets create SUPABASE_SERVICE_ROLE_KEY --data-file=-
   echo -n "value" | gcloud secrets create SUPABASE_DB_URL --data-file=-
   echo -n "value" | gcloud secrets create GOOGLE_CLOUD_PROJECT_NUMBER --data-file=-
   echo -n "value" | gcloud secrets create APPLE_APP_ID --data-file=-
   ```

5. **Set up Workload Identity Federation:**
   ```bash
   gcloud iam workload-identity-pools create github-pool \
     --location=global \
     --display-name="GitHub Actions Pool"

   gcloud iam workload-identity-pools providers create-oidc github-provider \
     --location=global \
     --workload-identity-pool=github-pool \
     --display-name="GitHub Provider" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --attribute-condition="assertion.repository=='YOUR_ORG/sticker-swapp-app'"
   ```

   Then grant the WIF service account deploy permissions (Cloud Run Developer, Artifact Registry Writer, Service Account User).

6. **Add GitHub Secrets:** `GCP_PROJECT_ID`, `WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT`

### Local Docker Testing

```bash
make docker-build              # Build image locally
make docker-run                # Run with local .env
curl localhost:8080/healthz    # Verify health check
```