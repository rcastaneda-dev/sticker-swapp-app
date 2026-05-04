# Deep Link Preservation Through Onboarding

## Overview

When a user taps a push notification to navigate to a specific match, but needs to complete onboarding steps first (age verification, guest migration, parental consent), the deep link destination is preserved and restored after onboarding completes.

## Architecture

### Components

1. **DeepLinkNotifier** ([deep_link_providers.dart](deep_link_providers.dart))
   - Stores the pending deep link destination (e.g., `/matches/abc123`)
   - Provides `consume()` to retrieve and clear the destination
   - Provides `clear()` to discard without using

2. **PushNotificationLifecycleProvider** ([push_notification_providers.dart](push_notification_providers.dart))
   - When notification is tapped, stores destination in `DeepLinkNotifier`
   - Also attempts immediate navigation (router handles redirects)

3. **Router Redirect Logic** ([../router/app_router.dart](../router/app_router.dart))
   - `_getDefaultDestination()` helper checks for pending deep link
   - Only consumes deep link when ALL onboarding is complete
   - Falls back to `/matches` if no pending destination

## Flow Examples

### Happy Path (Authenticated + Age Verified)
```
1. User taps notification for match-123
2. Deep link stored: /matches/match-123
3. Router checks: authenticated ✓, age-verified ✓, no migration ✓, no consent ✓
4. Router consumes deep link → navigates to /matches/match-123
```

### With Onboarding (New User)
```
1. User taps notification for match-456
2. Deep link stored: /matches/match-456
3. Router checks: not authenticated ✗ → redirects to /login
4. User logs in
5. Router checks: authenticated ✓, not age-verified ✗ → redirects to /age-verification
6. User verifies age
7. Router checks: authenticated ✓, age-verified ✓, no migration ✓, no consent ✓
8. Router consumes deep link → navigates to /matches/match-456
```

### Cold Start (App Killed)
```
1. App is killed
2. User taps notification for match-789
3. OneSignal click listener buffers match-789 in _pendingMatchId
4. App starts, lifecycle provider initializes
5. Lifecycle provider calls processPendingNotification()
6. Buffered notification processed → deep link stored: /matches/match-789
7. Router handles as per "Happy Path" or "With Onboarding" above
```

## Testing

- [deep_link_providers_test.dart](../../test/core/providers/deep_link_providers_test.dart)
  - Tests the DeepLinkNotifier state management

- [push_notification_providers_test.dart](../../test/core/providers/push_notification_providers_test.dart)
  - Tests that notification taps store the deep link
  - Tests that processPendingNotification is called during init

## Related Documentation

- Push Notifications: CLAUDE.md § Push Notifications
- Router: CLAUDE.md § Auth Flow → Router redirect logic
