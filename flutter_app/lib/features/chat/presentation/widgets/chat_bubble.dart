import 'package:flutter/material.dart';
import 'package:flutter_app/features/chat/data/services/ably_service.dart';
import 'package:flutter_app/shared/theme/swapp_tokens.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: SwappTokens.spacingXxs),
        padding: const EdgeInsets.symmetric(
          horizontal: SwappTokens.spacingMd,
          vertical: SwappTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: isMine
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(SwappTokens.radiusLg),
            topRight: const Radius.circular(SwappTokens.radiusLg),
            bottomLeft: Radius.circular(
                isMine ? SwappTokens.radiusLg : SwappTokens.radiusSm),
            bottomRight: Radius.circular(
                isMine ? SwappTokens.radiusSm : SwappTokens.radiusLg),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isMine
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: SwappTokens.spacingXxs),
            Text(
              '${message.timestamp.hour.toString().padLeft(2, '0')}:'
              '${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isMine
                        ? colorScheme.onPrimary.withValues(alpha: 0.7)
                        : colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
