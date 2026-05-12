import 'dart:async';

import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:flutter_app/features/chat/data/services/ably_service.dart';

/// In-memory Ably service for integration tests.
///
/// Does not open any WebSocket connections. Provides controllable streams
/// for chat messages and events.
class FakeAblyService extends AblyService {
  bool connectCalled = false;
  bool _isConnected = false;
  final Map<String, StreamController<ChatMessage>> _messageControllers = {};
  final Map<String, Map<String, StreamController<Map<String, dynamic>>>>
      _eventControllers = {};

  FakeAblyService()
      : super(
          config: const AblyConfig(tradingEngineBaseUrl: 'https://fake'),
        );

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<ably.ConnectionStateChange>? get connectionStateStream => null;

  @override
  Future<void> connect() async {
    connectCalled = true;
    _isConnected = true;
  }

  @override
  Future<Stream<ChatMessage>> joinMatchChannel(String matchId) async {
    _messageControllers.putIfAbsent(
      matchId,
      () => StreamController<ChatMessage>.broadcast(),
    );
    return _messageControllers[matchId]!.stream;
  }

  @override
  Future<void> sendMessage(String matchId, String body) async {
    // No-op — the ChatNotifier handles optimistic adds
  }

  @override
  Future<List<ChatMessage>> getHistory(String matchId,
      {int limit = 50}) async {
    return [];
  }

  @override
  Future<void> setTyping(String matchId, bool isTyping) async {}

  @override
  Stream<ably.PresenceMessage>? getPresenceStream(String matchId) => null;

  @override
  Future<List<String>> getPresence(String matchId) async => [];

  @override
  Future<void> leaveMatchChannel(String matchId) async {
    await _messageControllers[matchId]?.close();
    _messageControllers.remove(matchId);
  }

  @override
  Stream<Map<String, dynamic>>? subscribeToEvent(
      String matchId, String eventName) {
    _eventControllers
        .putIfAbsent(matchId, () => {})
        .putIfAbsent(
            eventName, () => StreamController<Map<String, dynamic>>.broadcast());
    return _eventControllers[matchId]![eventName]!.stream;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    for (final ctrl in _messageControllers.values) {
      await ctrl.close();
    }
    _messageControllers.clear();
  }

  /// Inject a message into a match channel's stream.
  void injectMessage(String matchId, ChatMessage message) {
    _messageControllers[matchId]?.add(message);
  }

  /// Inject an event into a match channel's event stream.
  void injectEvent(
      String matchId, String eventName, Map<String, dynamic> data) {
    _eventControllers[matchId]?[eventName]?.add(data);
  }
}
