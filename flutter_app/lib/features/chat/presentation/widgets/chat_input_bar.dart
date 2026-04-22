import 'package:flutter/material.dart';
import 'package:flutter_app/shared/theme/swapp_tokens.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: SwappTokens.spacingLg,
        right: SwappTokens.spacingSm,
        top: SwappTokens.spacingSm,
        bottom: MediaQuery.of(context).padding.bottom + SwappTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              enabled: enabled,
              maxLines: 4,
              minLines: 1,
              maxLength: 4000,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: enabled ? 'Type a message...' : 'Connecting...',
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(SwappTokens.radiusFull),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: SwappTokens.spacingLg,
                  vertical: SwappTokens.spacingSm,
                ),
              ),
            ),
          ),
          const SizedBox(width: SwappTokens.spacingSm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              return IconButton.filled(
                onPressed: hasText && enabled ? onSend : null,
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  backgroundColor: hasText && enabled
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  foregroundColor: hasText && enabled
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
