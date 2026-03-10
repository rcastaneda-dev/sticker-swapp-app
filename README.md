# World Cup 2026 Sticker Swap App

Monorepo containing:

- flutter_app → Mobile client
- go_service → Matchmaking and trading engine
- supabase → Database, migrations, and edge functions

## CI/CD Secrets

The CI pipeline requires the following GitHub secrets:

- APPSTORE_CONNECT_API_KEY
- APPSTORE_CONNECT_API_KEY_ID
- APPSTORE_CONNECT_ISSUER_ID
- PLAY_SERVICE_ACCOUNT_JSON
- ANDROID_KEYSTORE
- ANDROID_KEYSTORE_PASSWORD
- ANDROID_KEY_ALIAS
- ANDROID_KEY_PASSWORD
- IOS_CERTIFICATE
- IOS_CERTIFICATE_PASSWORD
- PROVISIONING_PROFILE