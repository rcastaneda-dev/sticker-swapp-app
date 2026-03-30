import 'package:flutter/material.dart';

import 'package:flutter_app/shared/shared.dart';
import '../../data/models/scored_match.dart';

/// Displays a single match candidate's information inside a card.
class TraderCard extends StatelessWidget {
  final ScoredMatch match;

  const TraderCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SwappCard(
      variant: SwappCardVariant.elevated,
      padding: const EdgeInsets.all(SwappTokens.spacingXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name + distance badge
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  _initials(match.displayName),
                  style: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: SwappTokens.spacingLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.displayName,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: SwappTokens.spacingXs),
                    _DistanceBadge(distance: match.formattedDistance),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: SwappTokens.spacingXl),

          // Match score
          _MatchScoreBar(score: match.totalScore),

          const SizedBox(height: SwappTokens.spacingXl),

          // Sticker exchange stats
          _ExchangeRow(
            icon: Icons.arrow_downward,
            label: 'They have stickers you need',
            count: match.theyHaveINeed,
            color: SwappColors.pitchGreen,
          ),
          const SizedBox(height: SwappTokens.spacingMd),
          _ExchangeRow(
            icon: Icons.arrow_upward,
            label: 'You have stickers they need',
            count: match.iHaveTheyNeed,
            color: SwappColors.gold,
          ),

          const SizedBox(height: SwappTokens.spacingXl),

          // Collection stats
          Row(
            children: [
              _StatChip(
                label: 'Duplicates',
                value: match.duplicateCount.toString(),
                icon: Icons.copy,
              ),
              const SizedBox(width: SwappTokens.spacingSm),
              _StatChip(
                label: 'Needed',
                value: match.neededCount.toString(),
                icon: Icons.search,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ── Private sub-widgets ─────────────────────────────────────────────────

class _DistanceBadge extends StatelessWidget {
  final String distance;
  const _DistanceBadge({required this.distance});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingMd,
        vertical: SwappTokens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on,
            size: 14,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: SwappTokens.spacingXs),
          Text(
            distance,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _MatchScoreBar extends StatelessWidget {
  final double score;
  const _MatchScoreBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final percentage = (score * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Match Score',
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              '$percentage%',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: SwappTokens.spacingSm),
        SwappProgressBar(
          current: percentage,
          total: 100,
          height: 8,
          showPercentage: false,
          activeColor: SwappColors.pitchGreen,
        ),
      ],
    );
  }
}

class _ExchangeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _ExchangeRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(SwappTokens.radiusMd),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: SwappTokens.spacingMd),
        Expanded(
          child: Text(label, style: textTheme.bodyMedium),
        ),
        Text(
          count.toString(),
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(SwappTokens.spacingMd),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(SwappTokens.radiusMd),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: SwappTokens.spacingSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
