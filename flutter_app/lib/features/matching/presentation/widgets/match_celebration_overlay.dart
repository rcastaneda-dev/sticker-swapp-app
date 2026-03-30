import 'package:flutter/material.dart';

import 'package:flutter_app/shared/shared.dart';
import '../../data/models/swipe_result.dart';

/// Full-screen overlay shown when a mutual match is created.
///
/// Animates in with an elastic scale and a background fade, then presents
/// "Open Chat" and "Keep Swiping" actions.
class MatchCelebrationOverlay extends StatefulWidget {
  final SwipeResult result;
  final VoidCallback onDismiss;
  final VoidCallback onOpenChat;

  const MatchCelebrationOverlay({
    super.key,
    required this.result,
    required this.onDismiss,
    required this.onOpenChat,
  });

  @override
  State<MatchCelebrationOverlay> createState() =>
      _MatchCelebrationOverlayState();
}

class _MatchCelebrationOverlayState extends State<MatchCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SwappTokens.animationSlow,
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ColoredBox(
          color: Colors.black.withValues(alpha: 0.7 * _fadeAnimation.value),
          child: Center(
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(SwappTokens.spacingXxl),
        child: SwappCard(
          variant: SwappCardVariant.elevated,
          padding: const EdgeInsets.all(SwappTokens.spacingXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: SwappColors.gold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.handshake,
                  size: 48,
                  color: SwappColors.gold,
                ),
              ),
              const SizedBox(height: SwappTokens.spacingXl),
              Text(
                "It's a Match!",
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SwappTokens.spacingSm),
              Text(
                'You both want to trade stickers.\nStart chatting to arrange the swap!',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SwappTokens.spacingXl),
              SwappButton(
                label: 'Open Chat',
                onPressed: widget.onOpenChat,
                variant: SwappButtonVariant.primary,
                size: SwappButtonSize.large,
                icon: Icons.chat,
                isExpanded: true,
              ),
              const SizedBox(height: SwappTokens.spacingSm),
              SwappButton(
                label: 'Keep Swiping',
                onPressed: widget.onDismiss,
                variant: SwappButtonVariant.outlined,
                size: SwappButtonSize.medium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
