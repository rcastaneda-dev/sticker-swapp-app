import 'package:flutter/material.dart';

import 'package:flutter_app/shared/shared.dart';

/// A shimmer-animated placeholder that mimics the [TraderCard] layout.
class TraderCardSkeleton extends StatefulWidget {
  const TraderCardSkeleton({super.key});

  @override
  State<TraderCardSkeleton> createState() => _TraderCardSkeletonState();
}

class _TraderCardSkeletonState extends State<TraderCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        return Opacity(opacity: _opacity.value, child: child);
      },
      child: SwappCard(
        variant: SwappCardVariant.elevated,
        padding: const EdgeInsets.all(SwappTokens.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + name + distance placeholder
            Row(
              children: [
                _SkeletonBox.circle(radius: 32),
                const SizedBox(width: SwappTokens.spacingLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBox(width: 140, height: 20),
                      const SizedBox(height: SwappTokens.spacingXs),
                      _SkeletonBox(width: 80, height: 16, borderRadius: SwappTokens.radiusFull),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: SwappTokens.spacingXl),

            // Match score placeholder
            _SkeletonBox(width: 100, height: 14),
            const SizedBox(height: SwappTokens.spacingSm),
            _SkeletonBox(width: double.infinity, height: 8, borderRadius: SwappTokens.radiusFull),

            const SizedBox(height: SwappTokens.spacingXl),

            // Exchange rows placeholder
            _buildRowPlaceholder(),
            const SizedBox(height: SwappTokens.spacingMd),
            _buildRowPlaceholder(),

            const SizedBox(height: SwappTokens.spacingXl),

            // Stat chips placeholder
            Row(
              children: [
                Expanded(child: _SkeletonBox(width: double.infinity, height: 52, borderRadius: SwappTokens.radiusMd)),
                const SizedBox(width: SwappTokens.spacingSm),
                Expanded(child: _SkeletonBox(width: double.infinity, height: 52, borderRadius: SwappTokens.radiusMd)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowPlaceholder() {
    return Row(
      children: [
        _SkeletonBox(width: 36, height: 36, borderRadius: SwappTokens.radiusMd),
        const SizedBox(width: SwappTokens.spacingMd),
        Expanded(child: _SkeletonBox(width: double.infinity, height: 14)),
        _SkeletonBox(width: 24, height: 18),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius = SwappTokens.radiusSm,
  });

  const _SkeletonBox.circle({required double radius})
      : width = radius * 2,
        height = radius * 2,
        borderRadius = radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
