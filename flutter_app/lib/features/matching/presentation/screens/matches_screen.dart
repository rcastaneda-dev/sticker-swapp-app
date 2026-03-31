import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/shared/shared.dart';
import '../../data/models/scored_match.dart';
import '../../data/providers/discovery_providers.dart';
import '../../data/providers/match_notification_providers.dart';
import '../widgets/match_celebration_overlay.dart';
import '../widgets/swipe_card_stack.dart';
import '../widgets/trader_card_skeleton.dart';

class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  final _stackKey = GlobalKey<SwipeCardStackState>();
  bool _initialized = false;
  String? _lastMatchedDisplayName;

  @override
  Widget build(BuildContext context) {
    final isUnder13 = ref.watch(isUnder13Provider) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sticker Swapp'),
        actions: [
          if (!isUnder13) const _MatchesBadgeIcon(),
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
        RefreshIndicator(
          onRefresh: () async {
            _initialized = false;
            await ref.read(discoveryProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                child: switch (discovery.status) {
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
                  DiscoveryStatus.loading => _buildSkeletonStack(),
                  DiscoveryStatus.ready => discovery.currentMatch != null
                      ? _buildCardStack(discovery)
                      : const Center(child: CircularProgressIndicator()),
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
                      subtitle: discovery.errorMessage ??
                          'Something went wrong.',
                      actionLabel: 'Try Again',
                      onAction: () {
                        _initialized = false;
                        ref.read(discoveryProvider.notifier).refresh();
                      },
                    ),
                },
              ),
            ],
          ),
        ),

        // Celebration overlay
        if (discovery.lastSwipeResult?.matched == true)
          Positioned.fill(
            child: MatchCelebrationOverlay(
              result: discovery.lastSwipeResult!,
              onDismiss: () {
                final result = discovery.lastSwipeResult!;
                final matchId = result.matchId!;
                final name = _lastMatchedDisplayName ?? 'a trader';
                ref.read(matchNotificationProvider.notifier).addMatch(
                      UnviewedMatch(matchId: matchId, displayName: name),
                    );
                ref.read(discoveryProvider.notifier).clearLastSwipeResult();
                _showMatchToast(matchId, name);
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

  Widget _buildSkeletonStack() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingLg,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: SwappTokens.spacingSm,
            ),
            child: Row(
              children: [
                Container(
                  width: 120,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius:
                        BorderRadius.circular(SwappTokens.radiusSm),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Behind skeleton
                Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..scale(0.95),
                    child: const Opacity(
                      opacity: 0.5,
                      child: IgnorePointer(
                        child: TraderCardSkeleton(),
                      ),
                    ),
                  ),
                ),
                // Top skeleton
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: TraderCardSkeleton(),
                ),
              ],
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
                _SkeletonCircleButton(),
                const SizedBox(width: SwappTokens.spacing3xl),
                _SkeletonCircleButton(),
              ],
            ),
          ),
        ],
      ),
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
                '${discovery.totalCount} traders nearby',
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
      _lastMatchedDisplayName = match.displayName;
      ref.read(discoveryProvider.notifier).swipeRight();
    } else {
      ref.read(discoveryProvider.notifier).swipeLeft();
    }
  }

  void _showMatchToast(String matchId, String displayName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.handshake, color: SwappColors.gold, size: 20),
            const SizedBox(width: SwappTokens.spacingSm),
            Expanded(child: Text('Matched with $displayName!')),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            ref.read(matchNotificationProvider.notifier).markViewed(matchId);
            context.push('/matches/$matchId');
          },
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

class _MatchesBadgeIcon extends ConsumerWidget {
  const _MatchesBadgeIcon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unviewedMatchCountProvider);
    final mostRecent = ref.watch(mostRecentUnviewedMatchProvider);

    return IconButton(
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count.toString()),
        child: const Icon(Icons.chat_bubble_outline),
      ),
      tooltip: 'Recent Matches',
      onPressed: mostRecent != null
          ? () {
              ref
                  .read(matchNotificationProvider.notifier)
                  .markViewed(mostRecent.matchId);
              context.push('/matches/${mostRecent.matchId}');
            }
          : null,
    );
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

class _SkeletonCircleButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
      ),
    );
  }
}
