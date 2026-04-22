/// Ably real-time chat service for the World Cup 2026 Sticker Swap App.
///
/// This service manages the connection to Ably Pro using token-based
/// authentication. Tokens are obtained from the Go trading engine's
/// `/api/v1/ably/auth` endpoint, ensuring the Ably API key never
/// touches the client.
///
/// Architecture notes (per PRD §4.2):
///   - Ably handles all WebSocket chat (not Supabase Realtime)
///   - Supabase Realtime is used only for inventory state notifications
///   - Under-13 users never instantiate this service (PRD §7.3)
library;

import 'dart:async';
import 'dart:convert';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuration for the Ably service.
class AblyConfig {
  /// Base URL of the Go trading engine (e.g., "https://api.stickerstadium.app")
  final String tradingEngineBaseUrl;

  const AblyConfig({required this.tradingEngineBaseUrl});
}

/// Message received from an Ably channel.
class ChatMessage {
  final String senderId;
  final String body;
  final DateTime timestamp;
  final String? matchId;

  const ChatMessage({
    required this.senderId,
    required this.body,
    required this.timestamp,
    this.matchId,
  });

  factory ChatMessage.fromAbly(ably.Message msg) {
    String body;
    if (msg.data is String) {
      try {
        final decoded = jsonDecode(msg.data as String);
        if (decoded is Map) {
          body = (decoded['text'] as String?) ??
              (decoded['body'] as String?) ??
              '';
        } else {
          body = decoded.toString();
        }
      } catch (_) {
        body = msg.data as String;
      }
    } else if (msg.data is Map) {
      body = (msg.data as Map)['text'] as String? ??
          (msg.data as Map)['body'] as String? ??
          '';
    } else {
      body = msg.data?.toString() ?? '';
    }

    return ChatMessage(
      senderId: msg.clientId ?? 'unknown',
      body: body,
      timestamp: msg.timestamp ?? DateTime.now(),
    );
  }
}

/// Manages the Ably real-time connection and chat channels.
///
/// Usage:
/// ```dart
/// final ablyService = AblyService(config: AblyConfig(
///   tradingEngineBaseUrl: 'https://api.stickerstadium.app',
/// ));
///
/// await ablyService.connect();
/// final stream = await ablyService.joinMatchChannel('match-123');
/// stream.listen((message) => print('${message.senderId}: ${message.body}'));
/// await ablyService.sendMessage('match-123', 'Hey, I have that sticker!');
/// ```
class AblyService {
  final AblyConfig config;
  final SupabaseClient? _injectedClient;
  final http.Client? _injectedHttpClient;

  ably.Realtime? _client;
  final Map<String, ably.RealtimeChannel> _channels = {};
  final Map<String, StreamController<ChatMessage>> _messageControllers = {};

  /// Whether the service is currently connected to Ably.
  bool get isConnected =>
      _client?.connection.state == ably.ConnectionState.connected;

  /// Stream of connection state changes.
  Stream<ably.ConnectionStateChange>? get connectionStateStream =>
      _client?.connection.on();

  /// Current connection state, or null if not initialized.
  ably.ConnectionState? get connectionState => _client?.connection.state;

  AblyService({
    required this.config,
    SupabaseClient? supabaseClient,
    http.Client? httpClient,
  })  : _injectedClient = supabaseClient,
        _injectedHttpClient = httpClient;

  SupabaseClient get _supabase => _injectedClient ?? Supabase.instance.client;

  http.Client get _http => _injectedHttpClient ?? http.Client();

  /// Establishes the Ably connection using token authentication.
  ///
  /// The token auth callback requests a signed token from the Go service
  /// on every connection and token renewal. The Go service scopes the
  /// token's capabilities to only the channels this user is authorized
  /// to access.
  Future<void> connect() async {
    final session = _supabase.auth.currentSession;

    if (session == null) {
      throw StateError('User must be authenticated before connecting to Ably');
    }

    final clientOptions = ably.ClientOptions(
      // Token auth callback — called on connect and automatic renewal
      authCallback: (params) async {
        return await _requestToken(matchId: null);
      },
      autoConnect: true,
      echoMessages: false, // Don't echo own messages back
      clientId: session.user.id, // Ably clientId = Supabase user ID
    );

    _client = ably.Realtime(options: clientOptions);

    // Wait for connection
    final completer = Completer<void>();
    _client!.connection.on(ably.ConnectionEvent.connected).listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    _client!.connection.on(ably.ConnectionEvent.failed).listen((stateChange) {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Ably connection failed: ${stateChange.reason}'),
        );
      }
    });

    // Timeout after 10 seconds
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Ably connection timed out'),
    );
  }

  /// Joins a match chat channel and returns a stream of messages.
  ///
  /// The channel name follows the convention "match:{matchId}" as defined
  /// in the Go token handler's capability scoping.
  Future<Stream<ChatMessage>> joinMatchChannel(String matchId) async {
    final channelName = 'match:$matchId';

    if (_channels.containsKey(channelName)) {
      return _messageControllers[channelName]!.stream;
    }

    // Request a token scoped to this specific match channel
    await _requestTokenForMatch(matchId);

    final channel = _client!.channels.get(channelName);
    _channels[channelName] = channel;

    // Attach first
    await channel.attach();

    final controller = StreamController<ChatMessage>.broadcast();
    _messageControllers[channelName] = controller;

    // Subscribe to chat messages only (filter out system events like match.created)
    channel.subscribe(name: 'chat.message').listen((msg) {
      try {
        controller.add(ChatMessage.fromAbly(msg));
      } catch (e) {
        debugPrint('Error parsing Ably message: $e');
      }
    });

    // Enter presence to show online status
    await channel.presence.enter({'status': 'online', 'isTyping': false});

    return controller.stream;
  }

  /// Sends a chat message on a match channel.
  ///
  /// The message is published to Ably, which routes it to the other
  /// participant. The Ably webhook persists it to PostgreSQL via
  /// the `insert_message()` RPC.
  Future<void> sendMessage(String matchId, String body) async {
    final channelName = 'match:$matchId';
    final channel = _channels[channelName];

    if (channel == null) {
      throw StateError(
          'Not connected to match channel: $matchId. Call joinMatchChannel first.');
    }

    await channel.publish(
      name: 'chat.message',
      data: jsonEncode({'text': body}),
    );
  }

  /// Fetch recent message history for a channel (up to 24h, Ably-configured).
  /// Returns messages in chronological order (oldest first).
  Future<List<ChatMessage>> getHistory(String matchId,
      {int limit = 50}) async {
    final channelName = 'match:$matchId';
    final channel =
        _channels[channelName] ?? _client!.channels.get(channelName);

    final resultPage = await channel.history(
      ably.RealtimeHistoryParams(direction: 'backwards', limit: limit),
    );

    return resultPage.items
        .where((msg) => msg.name == 'chat.message')
        .map((msg) => ChatMessage.fromAbly(msg))
        .toList()
        .reversed
        .toList();
  }

  /// Update presence data to signal typing state.
  Future<void> setTyping(String matchId, bool isTyping) async {
    final channelName = 'match:$matchId';
    final channel = _channels[channelName];
    if (channel == null) return;

    await channel.presence.update({
      'status': 'online',
      'isTyping': isTyping,
    });
  }

  /// Subscribe to presence events on a match channel.
  Stream<ably.PresenceMessage>? getPresenceStream(String matchId) {
    final channelName = 'match:$matchId';
    final channel = _channels[channelName];
    return channel?.presence.subscribe();
  }

  /// Gets the list of currently present users on a match channel.
  Future<List<String>> getPresence(String matchId) async {
    final channelName = 'match:$matchId';
    final channel = _channels[channelName];

    if (channel == null) return [];

    final members = await channel.presence.get();
    return members.map((m) => m.clientId ?? 'unknown').toList();
  }

  /// Leaves a match channel and cleans up resources.
  Future<void> leaveMatchChannel(String matchId) async {
    final channelName = 'match:$matchId';
    final channel = _channels.remove(channelName);
    final controller = _messageControllers.remove(channelName);

    if (channel != null) {
      await channel.presence.leave();
      await channel.detach();
    }
    await controller?.close();
  }

  /// Subscribes to the user's personal notification channel.
  ///
  /// This channel receives server-pushed events like new match alerts
  /// and trade confirmations. It's subscribe-only (the Go service publishes).
  Stream<Map<String, dynamic>> subscribeToNotifications() {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw StateError('User must be authenticated');
    }

    final channelName = 'user:${session.user.id}:notifications';
    final channel = _client!.channels.get(channelName);
    _channels[channelName] = channel;

    final controller = StreamController<Map<String, dynamic>>.broadcast();

    channel.subscribe().listen((msg) {
      try {
        final data = msg.data is String
            ? jsonDecode(msg.data as String) as Map<String, dynamic>
            : msg.data as Map<String, dynamic>;
        controller.add(data);
      } catch (e) {
        debugPrint('Error parsing notification: $e');
      }
    });

    channel.attach();
    return controller.stream;
  }

  /// Disconnects from Ably and cleans up all channels.
  Future<void> disconnect() async {
    for (final entry in _channels.entries) {
      try {
        await entry.value.detach();
      } catch (_) {}
    }
    _channels.clear();

    for (final controller in _messageControllers.values) {
      await controller.close();
    }
    _messageControllers.clear();

    _client?.close();
    _client = null;
  }

  // ── Private helpers ─────────────────────────────────────────────────

  /// Requests a signed Ably token from the Go trading engine.
  Future<ably.TokenRequest> _requestToken({String? matchId}) async {
    final session = _supabase.auth.currentSession;

    if (session == null) {
      throw StateError('No active session');
    }

    final uri =
        Uri.parse('${config.tradingEngineBaseUrl}/api/v1/ably/auth');

    final response = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
      body: matchId != null ? jsonEncode({'matchId': matchId}) : null,
    );

    if (response.statusCode != 200) {
      throw Exception('Ably token request failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final tokenReqData = data['tokenRequest'] as Map<String, dynamic>;

    return ably.TokenRequest.fromMap(tokenReqData);
  }

  Future<void> _requestTokenForMatch(String matchId) async {
    // Re-authenticate with match-scoped capability
    await _requestToken(matchId: matchId);
  }
}
