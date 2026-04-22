import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/chat/data/providers/chat_providers.dart';
import 'package:flutter_app/features/chat/data/services/ably_service.dart';
import 'package:flutter_app/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter_app/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:flutter_app/features/chat/presentation/widgets/chat_input_bar.dart';
import 'package:flutter_app/features/chat/presentation/widgets/connection_status_banner.dart';
import 'package:flutter_app/features/chat/presentation/widgets/typing_indicator.dart';
import 'package:flutter_app/shared/shared.dart';

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

class _StubChatNotifier extends ChatNotifier {
  final ChatState _initial;

  _StubChatNotifier(super.matchId, this._initial);

  @override
  ChatState build() => _initial;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> sendMessage(String body) async {}

  @override
  void onTypingChanged(String text) {}

  @override
  Future<void> cleanup() async {}
}

Widget _buildSubject({
  Map<String, dynamic>? metadata,
  ChatState? chatState,
}) {
  final state = chatState ?? const ChatState();

  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        () => _StubAuthStateNotifier(_authenticated(metadata: metadata)),
      ),
      chatProvider.overrideWith2(
        (matchId) => _StubChatNotifier(matchId, state),
      ),
    ],
    child: MaterialApp(
      theme: SwappTheme.light,
      home: const ChatScreen(matchId: 'test-match-123'),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('ChatScreen', () {
    testWidgets('shows restricted empty state for under-13 users',
        (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'is_under_13': true,
        'age_verified_at': '2024-01-01T00:00:00Z',
        'parental_consent_at': '2024-06-01T00:00:00Z',
      }));

      expect(find.text('Chat Not Available'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byType(ChatInputBar), findsNothing);
    });

    testWidgets('shows loading indicator during history load', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(isLoadingHistory: true),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no messages', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.connected,
        ),
      ));

      expect(find.text('No messages yet. Say hello!'), findsOneWidget);
    });

    testWidgets('renders sent messages right-aligned', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: ChatState(
          connectionStatus: ChatConnectionStatus.connected,
          messages: [
            ChatMessage(
              senderId: 'test-user-id',
              body: 'My sent message',
              timestamp: DateTime(2026, 4, 15, 12, 0),
            ),
          ],
        ),
      ));

      expect(find.text('My sent message'), findsOneWidget);
      expect(find.byType(ChatBubble), findsOneWidget);

      final align = tester.widget<Align>(
        find.descendant(
          of: find.byType(ChatBubble),
          matching: find.byType(Align),
        ),
      );
      expect(align.alignment, Alignment.centerRight);
    });

    testWidgets('renders received messages left-aligned', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: ChatState(
          connectionStatus: ChatConnectionStatus.connected,
          messages: [
            ChatMessage(
              senderId: 'other-user',
              body: 'Their message',
              timestamp: DateTime(2026, 4, 15, 12, 0),
            ),
          ],
        ),
      ));

      expect(find.text('Their message'), findsOneWidget);

      final align = tester.widget<Align>(
        find.descendant(
          of: find.byType(ChatBubble),
          matching: find.byType(Align),
        ),
      );
      expect(align.alignment, Alignment.centerLeft);
    });

    testWidgets('shows connection banner when disconnected', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.disconnected,
        ),
      ));

      expect(find.byType(ConnectionStatusBanner), findsOneWidget);
      expect(find.text('Connection lost. Reconnecting...'), findsOneWidget);
    });

    testWidgets('hides connection banner when connected', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.connected,
        ),
      ));

      expect(find.text('Connection lost. Reconnecting...'), findsNothing);
      expect(find.text('Connecting...'), findsNothing);
    });

    testWidgets('shows typing indicator when other user is typing',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.connected,
          otherUserTyping: true,
        ),
      ));
      // Pump past staggered Future.delayed in TypingIndicator animations
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TypingIndicator), findsOneWidget);

      // Replace widget tree so TypingIndicator disposes its controllers
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hides typing indicator when other user is not typing',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.connected,
          otherUserTyping: false,
        ),
      ));

      expect(find.byType(TypingIndicator), findsNothing);
    });

    testWidgets('input bar is disabled when disconnected', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.disconnected,
        ),
      ));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('input bar is enabled when connected', (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.connected,
        ),
      ));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isTrue);
    });

    testWidgets('shows online subtitle when other user is online',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.connected,
          otherUserOnline: true,
        ),
      ));

      expect(find.text('online'), findsOneWidget);
    });

    testWidgets('shows typing subtitle when other user is typing',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        chatState: const ChatState(
          connectionStatus: ChatConnectionStatus.connected,
          otherUserOnline: true,
          otherUserTyping: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('typing...'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
