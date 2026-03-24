import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/shared/shared.dart';

class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnder13 = ref.watch(isUnder13Provider) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sticker Swapp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.collections_bookmark),
            tooltip: 'My Collection',
            onPressed: () => context.push('/catalog'),
          ),
        ],
      ),
      body: isUnder13
          ? SwappRestrictedEmptyState(
              icon: Icons.swap_horiz,
              title: 'Trading Unlocks Later',
              subtitle:
                  'Swipe matching is available for users 13 and older. '
                  'You can still browse and track your sticker collection!',
              actionLabel: 'Browse Stickers',
              onAction: () => context.push('/catalog'),
            )
          : const Center(child: Text('Matches')),
    );
  }
}
