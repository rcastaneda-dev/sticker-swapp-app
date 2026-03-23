import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/swapp_tokens.dart';
import '../utils/team_colors.dart';

/// Display size for sticker images, matching the 3 variant sizes
/// from the Supabase Storage bucket (Tasks #19/#20).
enum StickerImageSize {
  /// 64px — grid views, compact lists
  thumbnail(64),

  /// 256px — catalog browsing, swipe cards
  card(256),

  /// 512px — full sticker detail view
  detail(512);

  const StickerImageSize(this.pixels);
  final double pixels;
}

/// Displays a sticker image or a team-colored placeholder when no image is
/// available (i.e. before Panini releases official assets).
///
/// When [imageUrl] is non-null, renders a cached network image with a shimmer
/// loading state. On error or when [imageUrl] is null, renders a generated
/// placeholder using the team's national colors.
///
/// ```dart
/// SwappStickerImage(
///   stickerNumber: 42,
///   team: 'Argentina',
///   type: 'player',
///   size: StickerImageSize.card,
/// )
/// ```
class SwappStickerImage extends StatelessWidget {
  const SwappStickerImage({
    super.key,
    required this.stickerNumber,
    this.imageUrl,
    this.team,
    this.type,
    this.size = StickerImageSize.card,
    this.onTap,
  });

  /// Sticker catalog number (1–980).
  final int stickerNumber;

  /// CDN URL from the `stickers.image_url` column. Null = show placeholder.
  final String? imageUrl;

  /// Team name for placeholder color. Null for stadium/special stickers.
  final String? team;

  /// Sticker type: 'player', 'stadium', or 'legend'.
  final String? type;

  /// Which size variant to render.
  final StickerImageSize size;

  /// Optional tap callback.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dimension = size.pixels;

    final child = imageUrl != null
        ? _NetworkImage(
            imageUrl: imageUrl!,
            dimension: dimension,
            placeholder: _Placeholder(
              stickerNumber: stickerNumber,
              team: team,
              type: type,
              dimension: dimension,
            ),
          )
        : _Placeholder(
            stickerNumber: stickerNumber,
            team: team,
            type: type,
            dimension: dimension,
          );

    return SizedBox(
      width: dimension,
      height: dimension,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SwappTokens.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(SwappTokens.radiusLg),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// Cached network image with shimmer loading and error fallback.
class _NetworkImage extends StatelessWidget {
  const _NetworkImage({
    required this.imageUrl,
    required this.dimension,
    required this.placeholder,
  });

  final String imageUrl;
  final double dimension;
  final _Placeholder placeholder;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: dimension,
      height: dimension,
      fit: BoxFit.cover,
      placeholder: (context, url) => _ShimmerBox(dimension: dimension),
      errorWidget: (context, url, error) => placeholder,
    );
  }
}

/// Animated shimmer loading indicator.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({required this.dimension});
  final double dimension;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(-1.0 + 2.0 * _controller.value + 1.0, 0),
              colors: [
                colorScheme.surfaceContainerHighest,
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                colorScheme.surfaceContainerHighest,
              ],
            ),
          ),
          child: SizedBox.square(dimension: widget.dimension),
        );
      },
    );
  }
}

/// Generated placeholder with team colors, sticker number, and type icon.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.stickerNumber,
    required this.team,
    required this.type,
    required this.dimension,
  });

  final int stickerNumber;
  final String? team;
  final String? type;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (teamPrimary, teamSecondary) = TeamColors.forTeam(team);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgOpacity = isDark ? 0.25 : 0.15;

    final isSmall = dimension <= StickerImageSize.thumbnail.pixels;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: teamPrimary.withValues(alpha: bgOpacity),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(SwappTokens.radiusLg),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmall ? SwappTokens.spacingXs : SwappTokens.spacingSm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Team name badge (hidden on thumbnail size)
            if (!isSmall && team != null) ...[
              _TeamBadge(
                team: team!,
                textColor: teamSecondary,
                backgroundColor: teamPrimary,
                textTheme: textTheme,
              ),
              const SizedBox(height: SwappTokens.spacingXs),
            ],

            // Sticker number
            Text(
              '#$stickerNumber',
              style: (isSmall ? textTheme.titleSmall : textTheme.headlineMedium)
                  ?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),

            // Type icon (hidden on thumbnail size)
            if (!isSmall && type != null) ...[
              const SizedBox(height: SwappTokens.spacingXs),
              Icon(
                _iconForType(type!),
                size: dimension * 0.1,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconForType(String type) {
    return switch (type) {
      'player' => Icons.person_outline,
      'stadium' => Icons.stadium_outlined,
      'legend' => Icons.star_outline,
      _ => Icons.image_outlined,
    };
  }
}

/// Small pill badge showing the team name.
class _TeamBadge extends StatelessWidget {
  const _TeamBadge({
    required this.team,
    required this.textColor,
    required this.backgroundColor,
    required this.textTheme,
  });

  final String team;
  final Color textColor;
  final Color backgroundColor;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SwappTokens.spacingSm,
          vertical: SwappTokens.spacingXxs,
        ),
        child: Text(
          team,
          style: textTheme.labelSmall?.copyWith(color: textColor),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
