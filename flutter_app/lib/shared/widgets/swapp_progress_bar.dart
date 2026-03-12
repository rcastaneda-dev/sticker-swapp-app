import 'package:flutter/material.dart';

import '../theme/swapp_tokens.dart';

class SwappProgressBar extends StatelessWidget {
  const SwappProgressBar({
    super.key,
    required this.current,
    required this.total,
    this.label,
    this.showPercentage = true,
    this.height = 12.0,
    this.animate = true,
    this.activeColor,
    this.backgroundColor,
  });

  final int current;
  final int total;
  final String? label;
  final bool showPercentage;
  final double height;
  final bool animate;
  final Color? activeColor;
  final Color? backgroundColor;

  double get _fraction => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fraction = _fraction;
    final percentage = (fraction * 100).toStringAsFixed(1);

    final effectiveActiveColor = activeColor ?? colorScheme.tertiary;
    final effectiveBgColor =
        backgroundColor ?? colorScheme.surfaceContainerHighest;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null || showPercentage)
          Padding(
            padding: const EdgeInsets.only(bottom: SwappTokens.spacingSm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                if (label == null) const Spacer(),
                Text(
                  showPercentage
                      ? '$current / $total ($percentage%)'
                      : '$current / $total',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth * fraction;

                return Stack(
                  children: [
                    // Background
                    Container(
                      width: double.infinity,
                      height: height,
                      color: effectiveBgColor,
                    ),
                    // Foreground (animated)
                    AnimatedContainer(
                      duration: animate
                          ? SwappTokens.animationMedium
                          : Duration.zero,
                      curve: Curves.easeInOut,
                      width: barWidth,
                      height: height,
                      decoration: BoxDecoration(
                        color: effectiveActiveColor,
                        borderRadius:
                            BorderRadius.circular(SwappTokens.radiusFull),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
