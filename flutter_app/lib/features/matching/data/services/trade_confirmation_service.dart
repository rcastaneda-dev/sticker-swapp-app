import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a trade confirmation API call.
class TradeConfirmationResult {
  final bool callerConfirmed;
  final bool otherConfirmed;
  final bool bothConfirmed;
  final String matchStatus;

  const TradeConfirmationResult({
    required this.callerConfirmed,
    required this.otherConfirmed,
    required this.bothConfirmed,
    required this.matchStatus,
  });

  factory TradeConfirmationResult.fromJson(Map<String, dynamic> json) {
    return TradeConfirmationResult(
      callerConfirmed: json['caller_confirmed'] as bool? ?? false,
      otherConfirmed: json['other_confirmed'] as bool? ?? false,
      bothConfirmed: json['both_confirmed'] as bool? ?? false,
      matchStatus: json['match_status'] as String? ?? 'PENDING',
    );
  }
}

/// HTTP service for trade confirmation endpoints on the Go backend.
class TradeConfirmationService {
  final String _baseUrl;
  final SupabaseClient? _injectedClient;
  final http.Client? _injectedHttpClient;

  TradeConfirmationService({
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

  /// Confirm the trade for the current user.
  Future<TradeConfirmationResult> confirmTrade(String matchId) async {
    final uri = Uri.parse('$_baseUrl/api/v1/matches/$matchId/confirm');
    final response = await _http.post(uri, headers: _authHeaders);

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 409) {
      final error = json['error'] as String? ?? 'UNKNOWN';
      throw TradeConfirmationException(
        'Confirmation failed: $error',
        statusCode: response.statusCode,
        errorCode: error,
      );
    }

    if (response.statusCode != 200) {
      throw TradeConfirmationException(
        'Confirmation failed: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    return TradeConfirmationResult.fromJson(json);
  }

  /// Fetch the current confirmation state for a match.
  Future<TradeConfirmationResult> getConfirmationState(String matchId) async {
    final uri = Uri.parse('$_baseUrl/api/v1/matches/$matchId/confirm');
    final response = await _http.get(uri, headers: _authHeaders);

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw TradeConfirmationException(
        'Failed to get state: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    return TradeConfirmationResult.fromJson(json);
  }
}

class TradeConfirmationException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;

  const TradeConfirmationException(
    this.message, {
    this.statusCode,
    this.errorCode,
  });

  @override
  String toString() =>
      'TradeConfirmationException($statusCode): $message';
}
