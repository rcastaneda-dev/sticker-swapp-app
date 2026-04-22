import 'dart:async';

import 'package:ably_flutter/ably_flutter.dart' as ably;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/chat/data/providers/chat_providers.dart';
import 'package:flutter_app/features/chat/data/services/ably_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

AuthAuthenticated _authenticated({Map<String, dynamic>? metadata}) {
  final user = User(
    id: 'test-user-id',
    appMetadata: {},
    userMetadata: metadata ?? {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );
  return AuthAuthenticated(
    user: user,
    session: Session(
      accessToken: 'fake-access-token',
      tokenType: 'bearer',
      user: user,
    ),
  );
}

class _StubAuthStateNotifier extends AuthStateNotifier {
  final AppAuthState _initial;
  _StubAuthStateNotifier(this._initial);

  @override
  AppAuthState build() => _initial;
}

ChatMessage _msg({
  String senderId = 'other-user',
  String body = 'hello',
  DateTime? timestamp,
}) =>
    ChatMessage(
      senderId: senderId,
      body: body,
      timestamp: timestamp ?? DateTime(2026, 4, 15, 12, 0),
    );

// ── Fake AblyService ─────────────────────────────────────────────────────

class _FakeAblyService extends AblyService {
  bool connectCalled = false;
  bool joinCalled = false;
  bool leaveCalled = false;
  String? lastTypingMatchId;
  bool? lastTypingState;
  List<ChatMessage> historyToReturn = [];
  final StreamController<ChatMessage> messageController =
      StreamController<ChatMessage>.broadcast();
  bool shouldThrowOnConnect = false;

  _FakeAblyService()
      : super(
          config: const AblyConfig(tradingEngineBaseUrl: 'https://test'),
        );

  @override
  bool get isConnected => !shouldThrowOnConnect;

  @override
  Stream<ably.ConnectionStateChange>? get connectionStateStream => null;

  @override
  Future<void> connect() async {
    connectCalled = true;
    if (shouldThrowOnConnect) {
      throw Exception('Connection failed');
    }
  }

  @override
  Future<Stream<ChatMessage>> joinMatchChannel(String matchId) async {
    joinCalled = true;
    return messageController.stream;
  }

  @override
  Future<List<ChatMessage>> getHistory(String matchId,
      {int limit = 50}) async {
    return historyToReturn;
  }

  @override
  Future<void> sendMessage(String matchId, String body) async {}

  @override
  Future<void> setTyping(String matchId, bool isTyping) async {
    lastTypingMatchId = matchId;
    lastTypingState = isTyping;
  }

  @override
  Stream<ably.PresenceMessage>? getPresenceStream(String matchId) => null;

  @override
  Future<void> leaveMatchChannel(String matchId) async {
    leaveCalled = true;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('ChatNotifier', () {
    late ProviderContainer container;
    late _FakeAblyService fakeService;

    ProviderContainer createContainer({
      List<ChatMessage>? history,
      bool shouldThrow = false,
    }) {
      fakeService = _FakeAblyService()
        ..historyToReturn = history ?? []
        ..shouldThrowOnConnect = shouldThrow;

      return ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(
              _authenticated(metadata: {
                'is_under_13': false,
                'age_verified_at': '2024-01-01T00:00:00Z',
              }),
            ),
          ),
          ablyServiceProvider.overrideWithValue(fakeService),
        ],
      );
    }

    tearDown(() => container.dispose());

    test('initial state is initializing', () {
      container = createContainer();
      final state = container.read(chatProvider('match-1'));
      expect(state.connectionStatus, ChatConnectionStatus.initializing);
      expect(state.messages, isEmpty);
    });

    test('initialize loads history and transitions to connected', () async {
      final historyMessages = [
        _msg(body: 'first'),
        _msg(body: 'second'),
      ];
      container = createContainer(history: historyMessages);

      await container.read(chatProvider('match-1').notifier).initialize();

      final state = container.read(chatProvider('match-1'));
      expect(state.connectionStatus, ChatConnectionStatus.connected);
      expect(state.messages, hasLength(2));
      expect(state.messages[0].body, 'first');
      expect(state.messages[1].body, 'second');
      expect(state.isLoadingHistory, isFalse);
      expect(fakeService.joinCalled, isTrue);
    });

    test('initialize transitions to failed on connection error', () async {
      container = createContainer(shouldThrow: true);

      await container.read(chatProvider('match-1').notifier).initialize();

      final state = container.read(chatProvider('match-1'));
      expect(state.connectionStatus, ChatConnectionStatus.failed);
      expect(state.errorMessage, isNotNull);
    });

    test('sendMessage adds optimistic message', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();
      await container
          .read(chatProvider('match-1').notifier)
          .sendMessage('hello there');

      final state = container.read(chatProvider('match-1'));
      expect(state.messages, hasLength(1));
      expect(state.messages[0].body, 'hello there');
      expect(state.messages[0].senderId, 'test-user-id');
    });

    test('sendMessage ignores empty text', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();
      await container.read(chatProvider('match-1').notifier).sendMessage('  ');

      final state = container.read(chatProvider('match-1'));
      expect(state.messages, isEmpty);
    });

    test('sendMessage clears typing indicator', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();
      await container
          .read(chatProvider('match-1').notifier)
          .sendMessage('hello');

      expect(fakeService.lastTypingState, isFalse);
    });

    test('live messages from stream are appended', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();

      // Simulate a live message arriving
      fakeService.messageController.add(_msg(
        senderId: 'other-user',
        body: 'live message',
        timestamp: DateTime(2026, 4, 15, 13, 0),
      ));

      // Give the stream listener time to process
      await Future<void>.delayed(Duration.zero);

      final state = container.read(chatProvider('match-1'));
      expect(state.messages, hasLength(1));
      expect(state.messages[0].body, 'live message');
    });

    test('duplicate messages are deduped', () async {
      final historyMsg = _msg(
        senderId: 'other-user',
        body: 'hello',
        timestamp: DateTime(2026, 4, 15, 12, 0),
      );
      container = createContainer(history: [historyMsg]);

      await container.read(chatProvider('match-1').notifier).initialize();

      // Simulate the same message arriving via live stream
      fakeService.messageController.add(_msg(
        senderId: 'other-user',
        body: 'hello',
        timestamp: DateTime(2026, 4, 15, 12, 0, 1), // 1 second later
      ));

      await Future<void>.delayed(Duration.zero);

      final state = container.read(chatProvider('match-1'));
      expect(state.messages, hasLength(1)); // Not duplicated
    });

    test('onTypingChanged sets typing to true', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();
      container
          .read(chatProvider('match-1').notifier)
          .onTypingChanged('typing...');

      expect(fakeService.lastTypingMatchId, 'match-1');
      expect(fakeService.lastTypingState, isTrue);
    });

    test('onTypingChanged with empty text sets typing to false', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();
      container.read(chatProvider('match-1').notifier).onTypingChanged('');

      expect(fakeService.lastTypingState, isFalse);
    });

    test('cleanup calls leaveMatchChannel', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();
      await container.read(chatProvider('match-1').notifier).cleanup();

      expect(fakeService.leaveCalled, isTrue);
    });

    // ── Convenience provider tests ────────────────────────────────────────

    test('chatConnectedProvider reflects connected state', () async {
      container = createContainer();

      await container.read(chatProvider('match-1').notifier).initialize();

      expect(container.read(chatConnectedProvider('match-1')), isTrue);
    });

    test('chatConnectedProvider is false before initialization', () {
      container = createContainer();

      expect(container.read(chatConnectedProvider('match-1')), isFalse);
    });
  });
}
