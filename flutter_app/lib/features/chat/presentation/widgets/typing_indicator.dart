import 'package:flutter/material.dart';
import 'package:flutter_app/shared/theme/swapp_tokens.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) controller.repeat(reverse: true);
      });
      return controller;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingLg,
        vertical: SwappTokens.spacingSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _controllers[i],
            builder: (_, child) => Transform.translate(
              offset: Offset(0, -4 * _controllers[i].value),
              child: child,
            ),
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5),
              ),
            ),
          );
        }),
      ),
    );
  }
}
