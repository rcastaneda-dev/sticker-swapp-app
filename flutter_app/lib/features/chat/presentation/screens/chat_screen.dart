import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/chat/data/providers/chat_providers.dart';
import 'package:flutter_app/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:flutter_app/features/chat/presentation/widgets/chat_input_bar.dart';
import 'package:flutter_app/features/chat/presentation/widgets/connection_status_banner.dart';
import 'package:flutter_app/features/chat/presentation/widgets/typing_indicator.dart';
import 'package:flutter_app/shared/shared.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String matchId;

  const ChatScreen({super.key, required this.matchId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _initialized = false;
  ChatNotifier? _notifier;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _notifier?.cleanup();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: SwappTokens.animationFast,
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return time;
    }
    return '${dt.month}/${dt.day} $time';
  }

  @override
  Widget build(BuildContext context) {
    final isUnder13 = ref.watch(isUnder13Provider) ?? false;

    if (isUnder13) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trade Chat')),
        body: const SwappRestrictedEmptyState(
          icon: Icons.chat_bubble_outline,
          title: 'Chat Not Available',
          subtitle:
              'Messaging is available for users 13 and older. '
              'Your safety comes first!',
        ),
      );
    }

    final chatState = ref.watch(chatProvider(widget.matchId));
    final currentUserId = ref.watch(currentUserIdProvider);

    // Initialize once after first build
    if (!_initialized) {
      _initialized = true;
      _notifier = ref.read(chatProvider(widget.matchId).notifier);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifier?.initialize();
      });
    }

    // Auto-scroll when new messages arrive
    ref.listen<ChatState>(chatProvider(widget.matchId), (previous, next) {
      if (previous != null && next.messages.length > previous.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trade Chat'),
            if (chatState.otherUserOnline)
              Text(
                chatState.otherUserTyping ? 'typing...' : 'online',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: SwappColors.pitchGreen,
                    ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          ConnectionStatusBanner(matchId: widget.matchId),

          // Messages
          Expanded(
            child: chatState.isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _buildMessageList(chatState, currentUserId),
          ),

          // Typing indicator
          if (chatState.otherUserTyping)
            const Align(
              alignment: Alignment.centerLeft,
              child: TypingIndicator(),
            ),

          // Input bar
          ChatInputBar(
            controller: _textController,
            onSend: () {
              final text = _textController.text;
              if (text.trim().isEmpty) return;
              ref
                  .read(chatProvider(widget.matchId).notifier)
                  .sendMessage(text);
              _textController.clear();
            },
            onChanged: (text) {
              ref
                  .read(chatProvider(widget.matchId).notifier)
                  .onTypingChanged(text);
            },
            enabled: chatState.connectionStatus ==
                ChatConnectionStatus.connected,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(ChatState chatState, String? currentUserId) {
    if (chatState.messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Say hello!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingLg,
        vertical: SwappTokens.spacingSm,
      ),
      itemCount: chatState.messages.length,
      itemBuilder: (context, index) {
        final message = chatState.messages[index];
        final isMine = message.senderId == currentUserId;

        // Show timestamp divider if gap > 5 minutes from previous message
        final showTimestamp = index == 0 ||
            message.timestamp
                    .difference(chatState.messages[index - 1].timestamp)
                    .inMinutes >
                5;

        return Column(
          children: [
            if (showTimestamp)
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: SwappTokens.spacingMd),
                child: Text(
                  _formatTimestamp(message.timestamp),
                  style:
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                ),
              ),
            ChatBubble(
              message: message,
              isMine: isMine,
            ),
          ],
        );
      },
    );
  }
}
