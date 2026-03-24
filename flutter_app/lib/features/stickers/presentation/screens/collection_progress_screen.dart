import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/shared/shared.dart';
import '../../data/providers/collection_progress_providers.dart';

class CollectionProgressScreen extends ConsumerWidget {
  const CollectionProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allStickersAsync = ref.watch(allStickersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Collection Progress')),
      body: allStickersAsync.when(
        data: (_) => const _ProgressContent(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: SwappTokens.spacingLg),
              Text(
                'Failed to load progress',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: SwappTokens.spacingMd),
              SwappButton(
                label: 'Retry',
                onPressed: () => ref.invalidate(allStickersProvider),
                variant: SwappButtonVariant.outlined,
                size: SwappButtonSize.small,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Main Content ──────────────────────────────────────────────────

class _ProgressContent extends ConsumerWidget {
  const _ProgressContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamProgress = ref.watch(teamProgressProvider);

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _OverallProgressHero()),
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: SwappTokens.spacingLg,
          ),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                top: SwappTokens.spacingXl,
                bottom: SwappTokens.spacingMd,
              ),
              child: Text(
                'Progress by Team',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: SwappTokens.spacingLg,
          ),
          sliver: SliverList.builder(
            itemCount: teamProgress.length,
            itemBuilder: (context, index) =>
                _TeamProgressRow(progress: teamProgress[index]),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: SwappTokens.spacingXxl),
        ),
      ],
    );
  }
}

// ── Overall Progress Hero ─────────────────────────────────────────

class _OverallProgressHero extends ConsumerWidget {
  const _OverallProgressHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overall = ref.watch(overallProgressProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fraction = overall.total > 0
        ? (overall.owned / overall.total).clamp(0.0, 1.0)
        : 0.0;
    final percentage = (fraction * 100).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SwappTokens.spacingLg,
        SwappTokens.spacingLg,
        SwappTokens.spacingLg,
        0,
      ),
      child: SwappCard(
        variant: SwappCardVariant.elevated,
        padding: const EdgeInsets.all(SwappTokens.spacingXl),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: SwappTokens.animationMedium,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                '$percentage%',
                key: ValueKey<String>(percentage),
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.tertiary,
                ),
              ),
            ),
            const SizedBox(height: SwappTokens.spacingSm),
            AnimatedSwitcher(
              duration: SwappTokens.animationMedium,
              child: Text(
                '${overall.owned} of ${overall.total} stickers collected',
                key: ValueKey<int>(overall.owned),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: SwappTokens.spacingLg),
            SwappProgressBar(
              current: overall.owned,
              total: overall.total,
              showPercentage: false,
              height: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Team Progress Row ─────────────────────────────────────────────

class _TeamProgressRow extends StatelessWidget {
  const _TeamProgressRow({required this.progress});
  final TeamProgress progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (primary, _) = TeamColors.forTeam(progress.team);
    final pct = (progress.percentage * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: SwappTokens.spacingMd),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: primary,
          ),
          const SizedBox(width: SwappTokens.spacingMd),
          SizedBox(
            width: 100,
            child: Text(
              progress.team,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: SwappTokens.spacingMd),
          Expanded(
            child: SwappProgressBar(
              current: progress.owned,
              total: progress.total,
              showPercentage: false,
              height: 8,
              activeColor: primary,
            ),
          ),
          const SizedBox(width: SwappTokens.spacingMd),
          SizedBox(
            width: 72,
            child: AnimatedSwitcher(
              duration: SwappTokens.animationMedium,
              child: Text(
                '${progress.owned}/${progress.total} ($pct%)',
                key: ValueKey<int>(progress.owned),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
