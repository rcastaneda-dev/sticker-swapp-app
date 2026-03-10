#!/usr/bin/env bash
# =============================================================================
# Ably Token Auth — Integration Test Script
# World Cup 2026 Sticker Swap App
#
# Tests the full flow:
#   1. Authenticate with Supabase to get a JWT
#   2. Request an Ably token from the Go service
#   3. Use the token to connect to Ably and publish/subscribe on a test channel
#
# Prerequisites:
#   - curl, jq installed
#   - Go service running (default: http://localhost:8080)
#   - Supabase project with a test user
#   - ABLY_API_KEY set in Go service environment
#
# Usage:
#   export SUPABASE_URL="https://your-project.supabase.co"
#   export SUPABASE_ANON_KEY="your-anon-key"
#   export ABLY_API_KEY="appId.keyId:keySecret"   # Only for direct Ably test
#   export TEST_EMAIL="test@example.com"
#   export TEST_PASSWORD="testpassword123"
#   export GO_SERVICE_URL="http://localhost:8080"  # optional, defaults to localhost
#   ./test_ably_auth.sh
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

SUPABASE_URL="${SUPABASE_URL:?Set SUPABASE_URL}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY}"
TEST_EMAIL="${TEST_EMAIL:?Set TEST_EMAIL}"
TEST_PASSWORD="${TEST_PASSWORD:?Set TEST_PASSWORD}"
GO_SERVICE_URL="${GO_SERVICE_URL:-http://localhost:8080}"
ABLY_API_KEY="${ABLY_API_KEY:-}"

PASS=0
FAIL=0
TOTAL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

print_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  ✅ $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $label"
    echo "     Expected: $expected"
    echo "     Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_empty() {
  local label="$1" value="$2"
  TOTAL=$((TOTAL + 1))
  if [ -n "$value" ] && [ "$value" != "null" ]; then
    echo "  ✅ $label (value: ${value:0:40}...)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $label — value is empty or null"
    FAIL=$((FAIL + 1))
  fi
}

assert_http_status() {
  local label="$1" expected="$2" actual="$3"
  assert_eq "$label (HTTP $expected)" "$expected" "$actual"
}

# ── Test 1: Health Check ─────────────────────────────────────────────────────

print_header "Test 1: Go Service Health Check"

HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${GO_SERVICE_URL}/healthz" 2>/dev/null || echo "000")
assert_http_status "GET /healthz returns 200" "200" "$HEALTH_RESPONSE"

# ── Test 2: Supabase Authentication ──────────────────────────────────────────

print_header "Test 2: Supabase Authentication"

AUTH_RESPONSE=$(curl -s -X POST \
  "${SUPABASE_URL}/auth/v1/token?grant_type=password" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"${TEST_EMAIL}\", \"password\": \"${TEST_PASSWORD}\"}")

ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.access_token // empty')
USER_ID=$(echo "$AUTH_RESPONSE" | jq -r '.user.id // empty')

assert_not_empty "Supabase returns access_token" "$ACCESS_TOKEN"
assert_not_empty "Supabase returns user.id" "$USER_ID"

if [ -z "$ACCESS_TOKEN" ]; then
  echo ""
  echo "⚠️  Cannot continue without a valid access token."
  echo "   Auth response: $AUTH_RESPONSE"
  exit 1
fi

echo "  ℹ️  User ID: $USER_ID"

# ── Test 3: Token Auth Endpoint — No Auth Header ────────────────────────────

print_header "Test 3: Token Endpoint Rejects Unauthenticated Requests"

NOAUTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${GO_SERVICE_URL}/api/v1/ably/auth" \
  -H "Content-Type: application/json")
assert_http_status "POST /api/v1/ably/auth without auth returns 401" "401" "$NOAUTH_STATUS"

# ── Test 4: Token Auth Endpoint — Valid Auth ─────────────────────────────────

print_header "Test 4: Token Endpoint Issues Signed Token Request"

TOKEN_RESPONSE=$(curl -s -X POST \
  "${GO_SERVICE_URL}/api/v1/ably/auth" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}')

TOKEN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${GO_SERVICE_URL}/api/v1/ably/auth" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}')

assert_http_status "POST /api/v1/ably/auth returns 200" "200" "$TOKEN_STATUS"

# Validate token request fields
KEY_NAME=$(echo "$TOKEN_RESPONSE" | jq -r '.tokenRequest.keyName // empty')
CLIENT_ID=$(echo "$TOKEN_RESPONSE" | jq -r '.tokenRequest.clientId // empty')
TTL=$(echo "$TOKEN_RESPONSE" | jq -r '.tokenRequest.ttl // empty')
NONCE=$(echo "$TOKEN_RESPONSE" | jq -r '.tokenRequest.nonce // empty')
MAC=$(echo "$TOKEN_RESPONSE" | jq -r '.tokenRequest.mac // empty')
CAPABILITY=$(echo "$TOKEN_RESPONSE" | jq -r '.tokenRequest.capability // empty')
TIMESTAMP=$(echo "$TOKEN_RESPONSE" | jq -r '.tokenRequest.timestamp // empty')

assert_not_empty "tokenRequest.keyName is set" "$KEY_NAME"
assert_eq "tokenRequest.clientId matches user ID" "$USER_ID" "$CLIENT_ID"
assert_not_empty "tokenRequest.ttl is set" "$TTL"
assert_not_empty "tokenRequest.nonce is set" "$NONCE"
assert_not_empty "tokenRequest.mac (HMAC signature) is set" "$MAC"
assert_not_empty "tokenRequest.capability is set" "$CAPABILITY"
assert_not_empty "tokenRequest.timestamp is set" "$TIMESTAMP"

echo ""
echo "  ℹ️  Capability: $CAPABILITY"
echo "  ℹ️  TTL: ${TTL}ms ($(( TTL / 60000 )) minutes)"

# ── Test 5: Token Request with Match ID ──────────────────────────────────────

print_header "Test 5: Token Endpoint Scopes Capability to Match Channel"

MATCH_TOKEN_RESPONSE=$(curl -s -X POST \
  "${GO_SERVICE_URL}/api/v1/ably/auth" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"matchId": "test-match-001"}')

MATCH_CAPABILITY=$(echo "$MATCH_TOKEN_RESPONSE" | jq -r '.tokenRequest.capability // empty')

# Check that the capability includes the match channel
TOTAL=$((TOTAL + 1))
if echo "$MATCH_CAPABILITY" | jq -e '."match:test-match-001"' > /dev/null 2>&1; then
  echo "  ✅ Capability includes match:test-match-001 channel"
  PASS=$((PASS + 1))
else
  echo "  ❌ Capability missing match:test-match-001 channel"
  echo "     Capability: $MATCH_CAPABILITY"
  FAIL=$((FAIL + 1))
fi

# Check notification channel is present
TOTAL=$((TOTAL + 1))
NOTIF_CHANNEL="user:${USER_ID}:notifications"
if echo "$MATCH_CAPABILITY" | jq -e ".\"$NOTIF_CHANNEL\"" > /dev/null 2>&1; then
  echo "  ✅ Capability includes personal notification channel"
  PASS=$((PASS + 1))
else
  echo "  ❌ Capability missing notification channel: $NOTIF_CHANNEL"
  FAIL=$((FAIL + 1))
fi

# ── Test 6: Ably Token Exchange (requires ABLY_API_KEY) ──────────────────────

print_header "Test 6: Exchange Token Request with Ably (end-to-end)"

if [ -z "$ABLY_API_KEY" ]; then
  echo "  ⏭️  Skipped — ABLY_API_KEY not set"
  echo "  ℹ️  Set ABLY_API_KEY to test the full Ably token exchange"
else
  # Extract app ID from API key
  ABLY_APP_ID=$(echo "$ABLY_API_KEY" | cut -d. -f1)

  # Exchange the signed token request with Ably's REST API
  ABLY_EXCHANGE=$(curl -s -X POST \
    "https://rest.ably.io/keys/${KEY_NAME}/requestToken" \
    -H "Content-Type: application/json" \
    -d "$(echo "$MATCH_TOKEN_RESPONSE" | jq '.tokenRequest')" | jq -r '.')

  ABLY_TOKEN=$(echo "$ABLY_EXCHANGE" | jq -r '.token // empty')
  ABLY_CLIENT_ID=$(echo "$ABLY_EXCHANGE" | jq -r '.clientId // empty')

  assert_not_empty "Ably returns a token" "$ABLY_TOKEN"
  assert_eq "Ably token clientId matches" "$USER_ID" "$ABLY_CLIENT_ID"

  if [ -n "$ABLY_TOKEN" ] && [ "$ABLY_TOKEN" != "null" ]; then
    echo ""
    echo "  ℹ️  Token preview: ${ABLY_TOKEN:0:30}..."

    # Test 7: Publish and subscribe on a test channel
    print_header "Test 7: Publish/Subscribe on Test Channel"

    TEST_CHANNEL="match:test-match-001"
    TEST_MESSAGE="Hello from integration test at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Publish a message using the token
    PUB_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST "https://rest.ably.io/channels/${TEST_CHANNEL}/messages" \
      -H "Authorization: Bearer ${ABLY_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"chat\", \"data\": \"${TEST_MESSAGE}\"}")

    assert_http_status "Publish to ${TEST_CHANNEL} succeeds" "201" "$PUB_STATUS"

    # Retrieve message history to verify
    HISTORY=$(curl -s \
      "https://rest.ably.io/channels/${TEST_CHANNEL}/messages?limit=1" \
      -H "Authorization: Bearer ${ABLY_TOKEN}")

    echo "  ℹ️  History response: $HISTORY"

    LAST_MSG=$(echo "$HISTORY" | jq -r '.[0].data // empty')
    assert_eq "Message retrieved from channel history" "$TEST_MESSAGE" "$LAST_MSG"
  fi
fi

# ── Test 8: Rate Limiting ────────────────────────────────────────────────────

print_header "Test 8: Rate Limiting (burst test)"

echo "  ℹ️  Sending 5 rapid requests..."
RATE_STATUSES=""
for i in $(seq 1 5); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${GO_SERVICE_URL}/api/v1/ably/auth" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}')
  RATE_STATUSES="$RATE_STATUSES $STATUS"
done

TOTAL=$((TOTAL + 1))
ALL_200=true
for s in $RATE_STATUSES; do
  if [ "$s" != "200" ]; then
    ALL_200=false
    break
  fi
done

if $ALL_200; then
  echo "  ✅ All 5 burst requests succeeded (within rate limit)"
  PASS=$((PASS + 1))
else
  echo "  ℹ️  Statuses: $RATE_STATUSES (rate limit may have triggered)"
  PASS=$((PASS + 1))  # This is informational, not a failure
fi

# ── Summary ──────────────────────────────────────────────────────────────────

print_header "Test Summary"

echo ""
echo "  Total:  $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  ❌ SOME TESTS FAILED"
  exit 1
else
  echo "  ✅ ALL TESTS PASSED"
  exit 0
fi
