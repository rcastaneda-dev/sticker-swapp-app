import 'package:flutter_app/features/chat/data/providers/chat_providers.dart';
import 'package:flutter_app/features/chat/data/services/ably_service.dart';

/// In-memory chat notifier for integration tests.
///
/// Simulates connected state and echoes sent messages back into the list.
class FakeChatNotifier extends ChatNotifier {
  final ChatState _initial;
  bool initializeCalled = false;
  bool cleanupCalled = false;
  final List<String> sentMessages = [];

  FakeChatNotifier(super.matchId, [ChatState? initial])
      : _initial = initial ??
            const ChatState(
              connectionStatus: ChatConnectionStatus.connected,
            );

  @override
  ChatState build() => _initial;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    state = state.copyWith(
      connectionStatus: ChatConnectionStatus.connected,
    );
  }

  @override
  Future<void> sendMessage(String body) async {
    sentMessages.add(body);
    final message = ChatMessage(
      senderId: 'test-user-id',
      body: body.trim(),
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  @override
  void onTypingChanged(String text) {
    // No-op
  }

  @override
  Future<void> cleanup() async {
    cleanupCalled = true;
  }

  /// Simulate receiving a message from the other user.
  void receiveMessage(String body, {String senderId = 'match-user-1'}) {
    final message = ChatMessage(
      senderId: senderId,
      body: body,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }
}
