import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/chat/data/services/chat_service.dart';
import 'package:flutter_app/shared/shared.dart';
import 'package:ably_flutter/ably_flutter.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String matchId;

  const ChatScreen({super.key, required this.matchId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _controller = TextEditingController();

  final List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    final isUnder13 = ref.read(isUnder13Provider) ?? false;
    if (!isUnder13) {
      _initChat();
    }
  }

  Future<void> _initChat() async {
    await _chatService.connect();

    _chatService.subscribeToMessages(widget.matchId).listen((Message message) {
      setState(() {
        _messages.add(message.data.toString());
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    await _chatService.sendMessage(widget.matchId, text);

    _controller.clear();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trade Chat'),
      ),
      body: Column(
        children: [
          /// Messages
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_messages[index]),
                );
              },
            ),
          ),

          /// Message input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Send a message...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
