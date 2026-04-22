import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/chat/data/providers/chat_providers.dart';
import 'package:flutter_app/shared/theme/swapp_tokens.dart';

class ConnectionStatusBanner extends ConsumerWidget {
  final String matchId;

  const ConnectionStatusBanner({super.key, required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(chatProvider(matchId)).connectionStatus;

    if (status == ChatConnectionStatus.connected) {
      return const SizedBox.shrink();
    }

    final (String text, Color color, IconData icon) = switch (status) {
      ChatConnectionStatus.initializing => (
        'Connecting...',
        Theme.of(context).colorScheme.secondaryContainer,
        Icons.hourglass_top,
      ),
      ChatConnectionStatus.connecting => (
        'Reconnecting...',
        Theme.of(context).colorScheme.secondaryContainer,
        Icons.sync,
      ),
      ChatConnectionStatus.disconnected => (
        'Connection lost. Reconnecting...',
        Theme.of(context).colorScheme.errorContainer,
        Icons.cloud_off,
      ),
      ChatConnectionStatus.failed => (
        'Unable to connect',
        Theme.of(context).colorScheme.errorContainer,
        Icons.error_outline,
      ),
      _ => ('', Colors.transparent, Icons.info),
    };

    return AnimatedContainer(
      duration: SwappTokens.animationFast,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingLg,
        vertical: SwappTokens.spacingSm,
      ),
      color: color,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: SwappTokens.spacingSm),
          Text(text, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
