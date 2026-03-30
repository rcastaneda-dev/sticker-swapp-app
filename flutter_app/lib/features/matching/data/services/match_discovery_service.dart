import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/scored_match.dart';
import '../models/swipe_result.dart';

/// HTTP service for the Go matchmaking backend.
///
/// Calls `GET /api/v1/matches` for discovery and
/// `POST /api/v1/matches` for swipe actions.
class MatchDiscoveryService {
  final String _baseUrl;
  final SupabaseClient? _injectedClient;
  final http.Client? _injectedHttpClient;

  MatchDiscoveryService({
    required String baseUrl,
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl,
        _injectedClient = supabaseClient,
        _injectedHttpClient = httpClient;

  SupabaseClient get _supabase => _injectedClient ?? Supabase.instance.client;

  http.Client get _http => _injectedHttpClient ?? http.Client();

  Map<String, String> get _authHeaders {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) throw StateError('No active session');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Fetch scored match candidates from the Go matchmaking engine.
  Future<List<ScoredMatch>> fetchMatches({
    required double latitude,
    required double longitude,
    int radiusM = 5000,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/matches').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        'radius': radiusM.toString(),
      },
    );

    final response = await _http.get(uri, headers: _authHeaders);

    if (response.statusCode != 200) {
      throw MatchDiscoveryException(
        'Failed to fetch matches: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .map((json) => ScoredMatch.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Record a right-swipe on [targetUserId].
  ///
  /// Returns [SwipeResult] indicating whether a mutual match was created.
  Future<SwipeResult> swipeRight(String targetUserId) async {
    final uri = Uri.parse('$_baseUrl/api/v1/matches');

    final response = await _http.post(
      uri,
      headers: _authHeaders,
      body: jsonEncode({'target_user_id': targetUserId}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw MatchDiscoveryException(
        'Failed to record swipe: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    return SwipeResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

class MatchDiscoveryException implements Exception {
  final String message;
  final int? statusCode;

  const MatchDiscoveryException(this.message, {this.statusCode});

  @override
  String toString() => 'MatchDiscoveryException($statusCode): $message';
}
