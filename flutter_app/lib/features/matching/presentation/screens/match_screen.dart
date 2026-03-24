import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/shared/shared.dart';

class MatchScreen extends ConsumerWidget {
  final String matchId;

  const MatchScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnder13 = ref.watch(isUnder13Provider) ?? false;

    if (isUnder13) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trade Match')),
        body: const SwappRestrictedEmptyState(
          icon: Icons.swap_horiz,
          title: 'Trading Not Available',
          subtitle:
              'Real-time trading is available for users 13 and older. '
              'You can manage your wishlist from your collection.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Trade Match')),
      body: Center(
        child: ElevatedButton(
          child: const Text('Open Chat'),
          onPressed: () {
            context.goNamed('chat', pathParameters: {'matchId': matchId});
          },
        ),
      ),
    );
  }
}
