import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/shared/shared.dart';
import 'package:flutter_app/features/stickers/data/models/sticker.dart';
import '../../data/models/trade_history_item.dart';
import '../../data/providers/trade_history_providers.dart';

/// Trade History Screen - displays all completed trades for the current user.
///
/// Shows trades in reverse chronological order (newest first), with partner
/// names, sticker images, and timestamps. Supports empty state, loading, and
/// error states via AsyncValue pattern.
class TradeHistoryScreen extends ConsumerWidget {
  const TradeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tradesAsync = ref.watch(tradeHistoryListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trade History'),
      ),
      body: tradesAsync.when(
        data: (trades) => trades.isEmpty
            ? const _EmptyState()
            : _TradeHistoryList(trades: trades),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          onRetry: () => ref.invalidate(tradeHistoryListProvider),
        ),
      ),
    );
  }
}

// ── Trade History List ──────────────────────────────────────────────

class _TradeHistoryList extends StatelessWidget {
  const _TradeHistoryList({required this.trades});
  final List<TradeHistoryItem> trades;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(SwappTokens.spacingLg),
      itemCount: trades.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: SwappTokens.spacingMd),
      itemBuilder: (context, index) => _TradeHistoryCard(
        trade: trades[index],
      ),
    );
  }
}

// ── Trade History Card ──────────────────────────────────────────────

class _TradeHistoryCard extends StatelessWidget {
  const _TradeHistoryCard({required this.trade});
  final TradeHistoryItem trade;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SwappCard(
      variant: SwappCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Partner name and date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: SwappTokens.spacingSm),
                    Expanded(
                      child: Text(
                        trade.partnerDisplayName,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDate(trade.createdAt),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: SwappTokens.spacingMd),

          // Trade details: Given and Received
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Given stickers
              Expanded(
                child: _StickerSection(
                  label: 'You gave',
                  stickers: trade.givenStickers,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              ),

              const SizedBox(width: SwappTokens.spacingMd),

              // Swap icon
              Icon(
                Icons.swap_horiz_rounded,
                color: colorScheme.primary,
                size: 32,
              ),

              const SizedBox(width: SwappTokens.spacingMd),

              // Received stickers
              Expanded(
                child: _StickerSection(
                  label: 'You got',
                  stickers: trade.receivedStickers,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else {
      final months = date.month;
      final day = date.day;
      final monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${monthNames[months - 1]} $day';
    }
  }
}

// ── Sticker Section (Given/Received) ────────────────────────────────

class _StickerSection extends StatelessWidget {
  const _StickerSection({
    required this.label,
    required this.stickers,
    required this.colorScheme,
    required this.textTheme,
  });

  final String label;
  final List<Sticker> stickers;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SwappTokens.spacingSm),
        Wrap(
          spacing: SwappTokens.spacingXs,
          runSpacing: SwappTokens.spacingXs,
          children: stickers
              .map((sticker) => _StickerThumbnail(sticker: sticker))
              .toList(),
        ),
      ],
    );
  }
}

// ── Sticker Thumbnail ───────────────────────────────────────────────

class _StickerThumbnail extends StatelessWidget {
  const _StickerThumbnail({required this.sticker});
  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '#${sticker.stickerNumber} ${sticker.team ?? sticker.title}',
      child: SwappStickerImage(
        stickerNumber: sticker.stickerNumber,
        imageUrl: sticker.imageUrl,
        team: sticker.team,
        type: sticker.type,
        size: StickerImageSize.thumbnail,
      ),
    );
  }
}

// ── Empty State ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SwappTokens.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: SwappTokens.spacingLg),
            Text(
              'No trades yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: SwappTokens.spacingSm),
            Text(
              'Complete your first trade to see it here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error State ─────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SwappTokens.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: SwappTokens.spacingLg),
            Text(
              'Failed to load trades',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: SwappTokens.spacingSm),
            Text(
              'Check your connection and try again',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SwappTokens.spacingLg),
            SwappButton(
              onPressed: onRetry,
              label: 'Retry',
              variant: SwappButtonVariant.outlined,
              size: SwappButtonSize.medium,
            ),
          ],
        ),
      ),
    );
  }
}
