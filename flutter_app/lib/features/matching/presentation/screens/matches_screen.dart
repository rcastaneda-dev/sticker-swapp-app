import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/shared/shared.dart';
import '../../data/models/scored_match.dart';
import '../../data/providers/discovery_providers.dart';
import '../widgets/match_celebration_overlay.dart';
import '../widgets/swipe_card_stack.dart';

class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  final _stackKey = GlobalKey<SwipeCardStackState>();
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
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
          : _buildDiscoveryBody(),
    );
  }

  Widget _buildDiscoveryBody() {
    final discovery = ref.watch(discoveryProvider);

    // Trigger initialization once.
    if (!_initialized &&
        discovery.status == DiscoveryStatus.awaitingLocation) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(discoveryProvider.notifier).initialize();
      });
    }

    return Stack(
      children: [
        switch (discovery.status) {
          DiscoveryStatus.awaitingLocation => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_searching, size: 48),
                  SizedBox(height: SwappTokens.spacingLg),
                  Text('Getting your location...'),
                  SizedBox(height: SwappTokens.spacingLg),
                  CircularProgressIndicator(),
                ],
              ),
            ),
          DiscoveryStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
          DiscoveryStatus.ready => _buildCardStack(discovery),
          DiscoveryStatus.empty => SwappRestrictedEmptyState(
              icon: Icons.people_outline,
              title: 'No Traders Nearby',
              subtitle:
                  'No one with matching stickers is nearby right now. '
                  'Try again later or widen your search.',
              actionLabel: 'Refresh',
              onAction: () {
                _initialized = false;
                ref.read(discoveryProvider.notifier).refresh();
              },
            ),
          DiscoveryStatus.error => SwappRestrictedEmptyState(
              icon: Icons.error_outline,
              title: 'Oops!',
              subtitle: discovery.errorMessage ?? 'Something went wrong.',
              actionLabel: 'Try Again',
              onAction: () {
                _initialized = false;
                ref.read(discoveryProvider.notifier).refresh();
              },
            ),
        },

        // Celebration overlay
        if (discovery.lastSwipeResult?.matched == true)
          Positioned.fill(
            child: MatchCelebrationOverlay(
              result: discovery.lastSwipeResult!,
              onDismiss: () {
                ref.read(discoveryProvider.notifier).clearLastSwipeResult();
              },
              onOpenChat: () {
                final matchId = discovery.lastSwipeResult!.matchId!;
                ref.read(discoveryProvider.notifier).clearLastSwipeResult();
                context.push('/matches/$matchId');
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCardStack(DiscoveryState discovery) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SwappTokens.spacingLg,
            vertical: SwappTokens.spacingSm,
          ),
          child: Row(
            children: [
              Text(
                '${discovery.remainingCount} traders nearby',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SwappTokens.spacingLg,
            ),
            child: SwipeCardStack(
              key: _stackKey,
              currentMatch: discovery.currentMatch!,
              upcomingMatches: discovery.upcomingMatches,
              onSwiped: _onSwiped,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            bottom: SwappTokens.spacingXl,
            top: SwappTokens.spacingMd,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(
                icon: Icons.close,
                color: Theme.of(context).colorScheme.error,
                onTap: () => _stackKey.currentState?.swipe(SwipeDirection.left),
              ),
              const SizedBox(width: SwappTokens.spacing3xl),
              _ActionButton(
                icon: Icons.favorite,
                color: SwappColors.pitchGreen,
                onTap: () =>
                    _stackKey.currentState?.swipe(SwipeDirection.right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onSwiped(ScoredMatch match, SwipeDirection direction) {
    if (direction == SwipeDirection.right) {
      ref.read(discoveryProvider.notifier).swipeRight();
    } else {
      ref.read(discoveryProvider.notifier).swipeLeft();
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 64,
          height: 64,
          child: Icon(icon, color: color, size: 32),
        ),
      ),
    );
  }
}
