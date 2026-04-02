import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/shared/shared.dart';
import 'package:flutter_app/features/stickers/data/models/sticker.dart';
import 'package:flutter_app/features/stickers/data/providers/collection_progress_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/wishlist_providers.dart';

/// Wishlist view shown to under-13 users on the matches screen.
///
/// Displays stickers the user still needs, with a shareable link
/// so parents/friends can help find stickers offline.
class Under13WishlistView extends ConsumerWidget {
  const Under13WishlistView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlist = ref.watch(wishlistProvider);
    final progress = ref.watch(overallProgressProvider);
    final shareState = ref.watch(wishlistShareProvider);

    return CustomScrollView(
      slivers: [
        // Header card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SwappTokens.spacingLg,
              SwappTokens.spacingMd,
              SwappTokens.spacingLg,
              SwappTokens.spacingSm,
            ),
            child: SwappCard(
              variant: SwappCardVariant.elevated,
              padding: const EdgeInsets.all(SwappTokens.spacingLg),
              child: Column(
                children: [
                  Text(
                    'My Wishlist',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: SwappTokens.spacingSm),
                  Text(
                    '${wishlist.length} stickers needed',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: SwappTokens.spacingMd),
                  SwappProgressBar(
                    current: progress.owned,
                    total: progress.total,
                    label: 'Collection',
                    showPercentage: true,
                  ),
                  const SizedBox(height: SwappTokens.spacingMd),
                  SwappButton(
                    label: shareState.status == WishlistShareStatus.loading
                        ? 'Generating...'
                        : 'Share Wishlist',
                    icon: Icons.share,
                    isLoading:
                        shareState.status == WishlistShareStatus.loading,
                    onPressed:
                        shareState.status == WishlistShareStatus.loading
                            ? null
                            : () => _onShare(context, ref),
                    variant: SwappButtonVariant.primary,
                    size: SwappButtonSize.medium,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Sticker count label
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SwappTokens.spacingLg,
              vertical: SwappTokens.spacingXs,
            ),
            child: Text(
              '${wishlist.length} stickers',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),

        // Wishlist grid
        if (wishlist.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events, size: 64),
                  SizedBox(height: SwappTokens.spacingLg),
                  Text('Collection complete!'),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(SwappTokens.spacingSm),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount =
                    (constraints.crossAxisExtent / 100).floor().clamp(3, 6);
                return SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => RepaintBoundary(
                      child: _WishlistTile(sticker: wishlist[index]),
                    ),
                    childCount: wishlist.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: false,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: SwappTokens.spacingSm,
                    crossAxisSpacing: SwappTokens.spacingSm,
                    childAspectRatio: 0.75,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _onShare(BuildContext context, WidgetRef ref) async {
    await ref.read(wishlistShareProvider.notifier).generateShareLink();
    final state = ref.read(wishlistShareProvider);

    if (!context.mounted) return;

    if (state.status == WishlistShareStatus.success && state.shareUrl != null) {
      await Clipboard.setData(ClipboardData(text: state.shareUrl!));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: SwappTokens.spacingSm),
                Expanded(child: Text('Wishlist link copied!')),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else if (state.status == WishlistShareStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not generate share link. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Grid tile for a needed sticker — shown at reduced opacity.
class _WishlistTile extends StatelessWidget {
  const _WishlistTile({required this.sticker});
  final Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SwappCard(
      variant: SwappCardVariant.outlined,
      padding: const EdgeInsets.all(SwappTokens.spacingXs),
      child: Column(
        children: [
          Expanded(
            child: Opacity(
              opacity: 0.4,
              child: SwappStickerImage(
                stickerNumber: sticker.stickerNumber,
                imageUrl: sticker.imageUrl,
                team: sticker.team,
                type: sticker.type,
                size: StickerImageSize.thumbnail,
              ),
            ),
          ),
          const SizedBox(height: SwappTokens.spacingXs),
          Text(
            '#${sticker.stickerNumber}',
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sticker.team ?? sticker.title,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
