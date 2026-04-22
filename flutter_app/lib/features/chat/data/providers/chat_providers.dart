import 'dart:async';

import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/chat/data/services/ably_service.dart';

// ── Connection status ────────────────────────────────────────────────────

enum ChatConnectionStatus {
  initializing,
  connecting,
  connected,
  disconnected,
  failed,
}

// ── Chat state ───────────────────────────────────────────────────────────

class ChatState {
  final ChatConnectionStatus connectionStatus;
  final List<ChatMessage> messages;
  final bool isLoadingHistory;
  final bool otherUserTyping;
  final bool otherUserOnline;
  final String? errorMessage;

  const ChatState({
    this.connectionStatus = ChatConnectionStatus.initializing,
    this.messages = const [],
    this.isLoadingHistory = false,
    this.otherUserTyping = false,
    this.otherUserOnline = false,
    this.errorMessage,
  });

  ChatState copyWith({
    ChatConnectionStatus? connectionStatus,
    List<ChatMessage>? messages,
    bool? isLoadingHistory,
    bool? otherUserTyping,
    bool? otherUserOnline,
    String? Function()? errorMessage,
  }) {
    return ChatState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      messages: messages ?? this.messages,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      otherUserTyping: otherUserTyping ?? this.otherUserTyping,
      otherUserOnline: otherUserOnline ?? this.otherUserOnline,
      errorMessage:
          errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

// ── Chat notifier ────────────────────────────────────────────────────────

class ChatNotifier extends Notifier<ChatState> {
  final String _matchId;

  StreamSubscription<ChatMessage>? _messageSubscription;
  StreamSubscription<ably.PresenceMessage>? _presenceSubscription;
  StreamSubscription<ably.ConnectionStateChange>? _connectionSubscription;
  Timer? _typingDebounce;

  ChatNotifier(this._matchId);

  @override
  ChatState build() {
    ref.onDispose(() {
      _messageSubscription?.cancel();
      _presenceSubscription?.cancel();
      _connectionSubscription?.cancel();
      _typingDebounce?.cancel();
    });
    return const ChatState();
  }

  /// Connect to Ably, load history, subscribe to messages and presence.
  Future<void> initialize() async {
    final ablyService = ref.read(ablyServiceProvider);
    state = state.copyWith(connectionStatus: ChatConnectionStatus.initializing);

    try {
      // 1. Connect if not already connected
      if (!ablyService.isConnected) {
        await ablyService.connect();
      }

      // 2. Listen to connection state changes
      _connectionSubscription = ablyService.connectionStateStream?.listen(
        (stateChange) {
          final mapped = _mapConnectionState(stateChange.current);
          state = state.copyWith(connectionStatus: mapped);
        },
      );

      // 3. Load message history
      state = state.copyWith(isLoadingHistory: true);
      final history = await ablyService.getHistory(_matchId, limit: 50);
      state = state.copyWith(
        messages: history,
        isLoadingHistory: false,
      );

      // 4. Join channel and subscribe to live messages
      final messageStream = await ablyService.joinMatchChannel(_matchId);
      _messageSubscription = messageStream.listen((message) {
        // Skip messages already in history (dedup by senderId + body + timestamp)
        final isDuplicate = state.messages.any(
          (m) =>
              m.senderId == message.senderId &&
              m.body == message.body &&
              m.timestamp
                      .difference(message.timestamp)
                      .inSeconds
                      .abs() <
                  2,
        );
        if (!isDuplicate) {
          state = state.copyWith(
            messages: [...state.messages, message],
          );
        }
      });

      // 5. Subscribe to presence for typing indicators and online status
      final currentUserId = ref.read(currentUserIdProvider);
      _presenceSubscription = ablyService.getPresenceStream(_matchId)?.listen(
        (presenceMsg) {
          if (presenceMsg.clientId == currentUserId) return;

          if (presenceMsg.action == ably.PresenceAction.leave) {
            state = state.copyWith(
              otherUserOnline: false,
              otherUserTyping: false,
            );
          } else {
            final data = presenceMsg.data;
            final isTyping = data is Map && data['isTyping'] == true;
            state = state.copyWith(
              otherUserOnline: true,
              otherUserTyping: isTyping,
            );
          }
        },
      );

      state = state.copyWith(connectionStatus: ChatConnectionStatus.connected);
    } catch (e) {
      debugPrint('Chat initialization failed: $e');
      state = state.copyWith(
        connectionStatus: ChatConnectionStatus.failed,
        isLoadingHistory: false,
        errorMessage: () => 'Failed to connect to chat',
      );
    }
  }

  /// Send a message with optimistic local add.
  Future<void> sendMessage(String body) async {
    if (body.trim().isEmpty) return;
    final ablyService = ref.read(ablyServiceProvider);

    // Optimistic: add the message locally immediately
    final currentUserId = ref.read(currentUserIdProvider)!;
    final optimisticMessage = ChatMessage(
      senderId: currentUserId,
      body: body.trim(),
      timestamp: DateTime.now(),
      matchId: _matchId,
    );
    state = state.copyWith(
      messages: [...state.messages, optimisticMessage],
    );

    // Clear typing indicator
    _typingDebounce?.cancel();
    unawaited(ablyService.setTyping(_matchId, false));

    try {
      await ablyService.sendMessage(_matchId, body.trim());
    } catch (e) {
      debugPrint('Failed to send message: $e');
    }
  }

  /// Call on every text change to manage typing indicator.
  void onTypingChanged(String text) {
    final ablyService = ref.read(ablyServiceProvider);

    _typingDebounce?.cancel();

    if (text.isNotEmpty) {
      unawaited(ablyService.setTyping(_matchId, true));
      // Auto-clear typing after 3 seconds of inactivity
      _typingDebounce = Timer(const Duration(seconds: 3), () {
        unawaited(ablyService.setTyping(_matchId, false));
      });
    } else {
      unawaited(ablyService.setTyping(_matchId, false));
    }
  }

  /// Clean up channel subscription on screen exit.
  Future<void> cleanup() async {
    final ablyService = ref.read(ablyServiceProvider);
    _typingDebounce?.cancel();
    try {
      await ablyService.setTyping(_matchId, false);
      await ablyService.leaveMatchChannel(_matchId);
    } catch (_) {}
  }

  ChatConnectionStatus _mapConnectionState(ably.ConnectionState aState) {
    return switch (aState) {
      ably.ConnectionState.connected => ChatConnectionStatus.connected,
      ably.ConnectionState.connecting => ChatConnectionStatus.connecting,
      ably.ConnectionState.disconnected => ChatConnectionStatus.disconnected,
      ably.ConnectionState.suspended => ChatConnectionStatus.disconnected,
      ably.ConnectionState.failed => ChatConnectionStatus.failed,
      _ => ChatConnectionStatus.initializing,
    };
  }
}

// ── Providers ────────────────────────────────────────────────────────────

/// AblyService singleton.
final ablyServiceProvider = Provider<AblyService>((ref) {
  return AblyService(
    config: const AblyConfig(
      tradingEngineBaseUrl: String.fromEnvironment('GO_SERVICE_URL'),
    ),
  );
});

/// Per-match chat state, parameterized by matchId.
final chatProvider =
    NotifierProvider.family<ChatNotifier, ChatState, String>(
  (matchId) => ChatNotifier(matchId),
);

/// Convenience: is the current chat connected?
final chatConnectedProvider = Provider.family<bool, String>((ref, matchId) {
  return ref.watch(chatProvider(matchId)).connectionStatus ==
      ChatConnectionStatus.connected;
});

/// Convenience: is the other user typing?
final otherUserTypingProvider = Provider.family<bool, String>((ref, matchId) {
  return ref.watch(chatProvider(matchId)).otherUserTyping;
});
