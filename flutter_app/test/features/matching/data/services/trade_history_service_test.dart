import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app/features/matching/data/services/trade_history_service.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  final String? currentUserId;

  _FakeSupabaseClient({
    this.currentUserId,
  });

  @override
  GoTrueClient get auth => _FakeGoTrueClient(currentUserId);

  @override
  SupabaseQueryBuilder from(String table) {
    throw UnsupportedError(
      'This test uses a simplified fake client. '
      'For full integration testing, use a real Supabase client or mocktail.',
    );
  }
}

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  final String? userId;

  _FakeGoTrueClient(this.userId);

  @override
  User? get currentUser => userId != null
      ? User(
          id: userId!,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        )
      : null;
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('TradeHistoryService', () {
    test('throws when user is not authenticated', () {
      final client = _FakeSupabaseClient(currentUserId: null);
      final service = TradeHistoryService(client: client);

      expect(
        () => service.fetchTradeHistory(),
        throwsA(isA<Exception>()),
      );
    });

    // Note: Full integration tests for fetchTradeHistory would require
    // mocking the complex Supabase query builder chain. For comprehensive
    // testing, consider using:
    // 1. mocktail for more sophisticated mocking
    // 2. Integration tests with a real Supabase instance
    // 3. Widget tests that verify the full data flow
    //
    // The model tests (trade_history_test.dart) already cover the core
    // business logic for parsing and transforming trade data.
  });
}
