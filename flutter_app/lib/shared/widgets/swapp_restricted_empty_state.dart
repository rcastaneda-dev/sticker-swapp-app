import 'package:flutter/material.dart';

import '../theme/swapp_tokens.dart';
import 'swapp_button.dart';

/// A centered empty state for features restricted from under-13 users.
///
/// Displays an icon, title, descriptive subtitle, and optional action button.
class SwappRestrictedEmptyState extends StatelessWidget {
  const SwappRestrictedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SwappTokens.spacingXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: SwappTokens.spacingLg),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SwappTokens.spacingSm),
            Text(
              subtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: SwappTokens.spacingXl),
              SwappButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: SwappButtonVariant.outlined,
                size: SwappButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
