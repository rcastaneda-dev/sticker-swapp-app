import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app/features/matching/data/services/match_discovery_service.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeHttpClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  String responseBody = '[]';
  int responseStatus = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      responseStatus,
    );
  }
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => _FakeGoTrueClient();
}

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  Session? get currentSession => Session(
        accessToken: 'test-jwt-token',
        tokenType: 'bearer',
        user: User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  const baseUrl = 'https://api.example.com';
  late _FakeHttpClient httpClient;
  late MatchDiscoveryService service;

  setUp(() {
    httpClient = _FakeHttpClient();
    service = MatchDiscoveryService(
      baseUrl: baseUrl,
      supabaseClient: _FakeSupabaseClient(),
      httpClient: httpClient,
    );
  });

  group('fetchMatches', () {
    test('sends GET with correct query parameters', () async {
      httpClient.responseBody = '[]';
      httpClient.responseStatus = 200;

      await service.fetchMatches(
        latitude: 13.69,
        longitude: -89.21,
        radiusM: 3000,
      );

      final uri = httpClient.lastRequest!.url;
      expect(uri.path, '/api/v1/matches');
      expect(uri.queryParameters['lat'], '13.69');
      expect(uri.queryParameters['lng'], '-89.21');
      expect(uri.queryParameters['radius'], '3000');
    });

    test('includes authorization header', () async {
      httpClient.responseBody = '[]';
      httpClient.responseStatus = 200;

      await service.fetchMatches(latitude: 0, longitude: 0);

      expect(
        httpClient.lastRequest!.headers['Authorization'],
        'Bearer test-jwt-token',
      );
    });

    test('parses response into List<ScoredMatch>', () async {
      httpClient.responseBody = jsonEncode([
        {
          'user_id': 'u1',
          'display_name': 'Test User',
          'distance_m': 500.0,
          'duplicate_count': 10,
          'needed_count': 5,
          'they_have_i_need': 3,
          'i_have_they_need': 2,
          'proximity_score': 0.9,
          'reciprocal_score': 0.5,
          'activity_score': 0.8,
          'total_score': 0.76,
        },
      ]);
      httpClient.responseStatus = 200;

      final matches = await service.fetchMatches(latitude: 0, longitude: 0);

      expect(matches, hasLength(1));
      expect(matches.first.userId, 'u1');
      expect(matches.first.displayName, 'Test User');
      expect(matches.first.distanceM, 500.0);
    });

    test('returns empty list for empty response', () async {
      httpClient.responseBody = '[]';
      httpClient.responseStatus = 200;

      final matches = await service.fetchMatches(latitude: 0, longitude: 0);

      expect(matches, isEmpty);
    });

    test('throws MatchDiscoveryException on non-200', () async {
      httpClient.responseBody = '{"error":"unauthorized"}';
      httpClient.responseStatus = 401;

      expect(
        () => service.fetchMatches(latitude: 0, longitude: 0),
        throwsA(isA<MatchDiscoveryException>()),
      );
    });
  });

  group('swipeRight', () {
    test('sends POST with target_user_id body', () async {
      httpClient.responseBody = jsonEncode({
        'matched': false,
        'swipe_recorded': true,
      });
      httpClient.responseStatus = 200;

      await service.swipeRight('target-uuid');

      final request = httpClient.lastRequest!;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/matches');
    });

    test('returns SwipeResult for 200 (no match)', () async {
      httpClient.responseBody = jsonEncode({
        'matched': false,
        'swipe_recorded': true,
      });
      httpClient.responseStatus = 200;

      final result = await service.swipeRight('target-uuid');

      expect(result.matched, isFalse);
      expect(result.swipeRecorded, isTrue);
    });

    test('returns SwipeResult for 201 (mutual match)', () async {
      httpClient.responseBody = jsonEncode({
        'matched': true,
        'match_id': 'match-1',
        'user1_id': 'u1',
        'user2_id': 'u2',
        'status': 'PENDING',
        'created_at': '2026-03-30T12:00:00Z',
      });
      httpClient.responseStatus = 201;

      final result = await service.swipeRight('target-uuid');

      expect(result.matched, isTrue);
      expect(result.matchId, 'match-1');
      expect(result.status, 'PENDING');
    });

    test('throws MatchDiscoveryException on 500', () async {
      httpClient.responseBody = '{"error":"server error"}';
      httpClient.responseStatus = 500;

      expect(
        () => service.swipeRight('target-uuid'),
        throwsA(isA<MatchDiscoveryException>()),
      );
    });
  });
}
