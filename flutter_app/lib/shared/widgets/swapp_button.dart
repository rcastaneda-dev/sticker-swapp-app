import 'package:flutter/material.dart';

import '../theme/swapp_tokens.dart';

enum SwappButtonVariant { primary, secondary, outlined }

enum SwappButtonSize { small, medium, large }

class SwappButton extends StatelessWidget {
  const SwappButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SwappButtonVariant.primary,
    this.size = SwappButtonSize.medium,
    this.isLoading = false,
    this.icon,
    this.isExpanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final SwappButtonVariant variant;
  final SwappButtonSize size;
  final bool isLoading;
  final IconData? icon;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final double height;
    final TextStyle? textStyle;
    final double horizontalPadding;

    switch (size) {
      case SwappButtonSize.small:
        height = SwappTokens.buttonHeightSm;
        textStyle = theme.textTheme.labelMedium;
        horizontalPadding = SwappTokens.spacingMd;
      case SwappButtonSize.medium:
        height = SwappTokens.buttonHeightMd;
        textStyle = theme.textTheme.labelLarge;
        horizontalPadding = SwappTokens.spacingXl;
      case SwappButtonSize.large:
        height = SwappTokens.buttonHeightLg;
        textStyle = theme.textTheme.titleSmall;
        horizontalPadding = SwappTokens.spacingXxl;
    }

    final effectiveOnPressed = isLoading ? null : onPressed;
    final progressSize = (textStyle?.fontSize ?? 14.0) + 2;

    final Widget child = isLoading
        ? SizedBox(
            width: progressSize,
            height: progressSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _progressColor(context),
            ),
          )
        : Text(label);

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(isExpanded ? double.infinity : 0, height),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: horizontalPadding),
      ),
      textStyle: WidgetStatePropertyAll(textStyle),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
        ),
      ),
    );

    switch (variant) {
      case SwappButtonVariant.primary:
        if (icon != null && !isLoading) {
          return FilledButton.icon(
            onPressed: effectiveOnPressed,
            style: style,
            icon: Icon(icon, size: progressSize),
            label: child,
          );
        }
        return FilledButton(
          onPressed: effectiveOnPressed,
          style: style,
          child: child,
        );

      case SwappButtonVariant.secondary:
        if (icon != null && !isLoading) {
          return FilledButton.tonalIcon(
            onPressed: effectiveOnPressed,
            style: style,
            icon: Icon(icon, size: progressSize),
            label: child,
          );
        }
        return FilledButton.tonal(
          onPressed: effectiveOnPressed,
          style: style,
          child: child,
        );

      case SwappButtonVariant.outlined:
        if (icon != null && !isLoading) {
          return OutlinedButton.icon(
            onPressed: effectiveOnPressed,
            style: style,
            icon: Icon(icon, size: progressSize),
            label: child,
          );
        }
        return OutlinedButton(
          onPressed: effectiveOnPressed,
          style: style,
          child: child,
        );
    }
  }

  Color _progressColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (variant) {
      case SwappButtonVariant.primary:
        return colorScheme.onPrimary;
      case SwappButtonVariant.secondary:
        return colorScheme.onSecondaryContainer;
      case SwappButtonVariant.outlined:
        return colorScheme.primary;
    }
  }
}
