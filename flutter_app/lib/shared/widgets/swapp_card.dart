import 'package:flutter/material.dart';

import '../theme/swapp_tokens.dart';

enum SwappCardVariant { filled, elevated, outlined }

class SwappCard extends StatelessWidget {
  const SwappCard({
    super.key,
    required this.child,
    this.variant = SwappCardVariant.filled,
    this.padding,
    this.onTap,
    this.width,
    this.height,
  });

  final Widget child;
  final SwappCardVariant variant;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectivePadding =
        padding ?? const EdgeInsets.all(SwappTokens.spacingLg);

    final Color backgroundColor;
    final double elevation;
    final BorderSide borderSide;

    switch (variant) {
      case SwappCardVariant.filled:
        backgroundColor = colorScheme.surfaceContainerHighest;
        elevation = SwappTokens.elevationNone;
        borderSide = BorderSide.none;
      case SwappCardVariant.elevated:
        backgroundColor = colorScheme.surface;
        elevation = SwappTokens.elevationMd;
        borderSide = BorderSide.none;
      case SwappCardVariant.outlined:
        backgroundColor = colorScheme.surface;
        elevation = SwappTokens.elevationNone;
        borderSide = BorderSide(color: colorScheme.outlineVariant);
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SwappTokens.radiusLg),
      side: borderSide,
    );

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: backgroundColor,
        elevation: elevation,
        shadowColor: colorScheme.shadow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SwappTokens.radiusLg),
          child: Padding(
            padding: effectivePadding,
            child: child,
          ),
        ),
      ),
    );
  }
}
