import 'package:flutter/material.dart';

import 'package:flutter_app/shared/shared.dart';
import '../../data/models/scored_match.dart';
import 'trader_card.dart';

/// Direction of a completed swipe.
enum SwipeDirection { left, right }

/// Callback fired when the top card is swiped off screen.
typedef SwipeCallback = void Function(
    ScoredMatch match, SwipeDirection direction);

/// A Tinder-style draggable card stack.
///
/// The top card responds to horizontal pan gestures. Behind cards are
/// rendered with decreasing scale and opacity. Uses [RepaintBoundary]
/// and GPU-composited transforms for 120 FPS performance.
class SwipeCardStack extends StatefulWidget {
  /// The match shown on the top (interactive) card.
  final ScoredMatch currentMatch;

  /// 0-2 matches rendered behind the top card.
  final List<ScoredMatch> upcomingMatches;

  /// Called after the swipe-off animation completes.
  final SwipeCallback onSwiped;

  const SwipeCardStack({
    super.key,
    required this.currentMatch,
    required this.upcomingMatches,
    required this.onSwiped,
  });

  @override
  State<SwipeCardStack> createState() => SwipeCardStackState();
}

class SwipeCardStackState extends State<SwipeCardStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Alignment _dragAlignment = Alignment.center;
  Animation<Alignment>? _animation;
  bool _isSwiping = false;

  static const double _swipeThreshold = 0.3;
  static const double _flingVelocity = 800.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SwappTokens.animationMedium,
    );
    _controller.addListener(() {
      if (_animation != null) {
        setState(() {
          _dragAlignment = _animation!.value;
        });
      }
    });
  }

  @override
  void didUpdateWidget(SwipeCardStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMatch.userId != widget.currentMatch.userId) {
      _dragAlignment = Alignment.center;
      _controller.reset();
      _isSwiping = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Gesture handlers ──────────────────────────────────────────────────

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isSwiping) return;
    final size = MediaQuery.of(context).size;
    setState(() {
      _dragAlignment += Alignment(
        details.delta.dx / (size.width / 2),
        details.delta.dy / (size.height / 2),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isSwiping) return;

    final velocity = details.velocity.pixelsPerSecond.dx;
    final dragX = _dragAlignment.x;

    if (dragX > _swipeThreshold || velocity > _flingVelocity) {
      _animateOff(SwipeDirection.right);
    } else if (dragX < -_swipeThreshold || velocity < -_flingVelocity) {
      _animateOff(SwipeDirection.left);
    } else {
      _animateBack();
    }
  }

  // ── Animations ────────────────────────────────────────────────────────

  void _animateOff(SwipeDirection direction) {
    _isSwiping = true;
    final targetX = direction == SwipeDirection.right ? 3.0 : -3.0;
    _animation = _controller.drive(
      AlignmentTween(
        begin: _dragAlignment,
        end: Alignment(targetX, _dragAlignment.y * 0.5),
      ),
    );
    _controller.forward(from: 0).then((_) {
      widget.onSwiped(widget.currentMatch, direction);
      _dragAlignment = Alignment.center;
      _controller.reset();
      _isSwiping = false;
    });
  }

  void _animateBack() {
    _animation = _controller.drive(
      AlignmentTween(
        begin: _dragAlignment,
        end: Alignment.center,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
    );
    _controller.forward(from: 0);
  }

  /// Programmatic swipe (for the action buttons).
  void swipe(SwipeDirection direction) {
    if (_isSwiping) return;
    _animateOff(direction);
  }

  // ── Derived values ────────────────────────────────────────────────────

  double get _rotation => _dragAlignment.x * 0.1;

  double get _likeOpacity =>
      (_dragAlignment.x / _swipeThreshold).clamp(0.0, 1.0);

  double get _skipOpacity =>
      (-_dragAlignment.x / _swipeThreshold).clamp(0.0, 1.0);

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Behind cards (back to front)
            for (int i = widget.upcomingMatches.length - 1; i >= 0; i--)
              _buildBehindCard(i, constraints),

            // Top card (interactive)
            _buildTopCard(constraints),
          ],
        );
      },
    );
  }

  Widget _buildBehindCard(int behindIndex, BoxConstraints constraints) {
    final scaleFactor = 1.0 - (behindIndex + 1) * 0.05;
    final yOffset = (behindIndex + 1) * 10.0;

    return RepaintBoundary(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scaleByDouble(scaleFactor, scaleFactor, scaleFactor, 1.0)
          ..translateByDouble(0.0, yOffset, 0.0, 0.0),
        child: Opacity(
          opacity: 0.9 - behindIndex * 0.15,
          child: IgnorePointer(
            child: SizedBox(
              width: constraints.maxWidth,
              child: TraderCard(match: widget.upcomingMatches[behindIndex]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopCard(BoxConstraints constraints) {
    return RepaintBoundary(
      child: GestureDetector(
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Align(
          alignment: _dragAlignment,
          child: Transform.rotate(
            angle: _rotation,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Stack(
                children: [
                  TraderCard(match: widget.currentMatch),
                  // "TRADE" stamp (right swipe)
                  if (_likeOpacity > 0)
                    Positioned(
                      top: SwappTokens.spacingXl,
                      left: SwappTokens.spacingXl,
                      child: Opacity(
                        opacity: _likeOpacity,
                        child: const _SwipeLabel(
                          text: 'TRADE',
                          color: SwappColors.pitchGreen,
                        ),
                      ),
                    ),
                  // "SKIP" stamp (left swipe)
                  if (_skipOpacity > 0)
                    Positioned(
                      top: SwappTokens.spacingXl,
                      right: SwappTokens.spacingXl,
                      child: Opacity(
                        opacity: _skipOpacity,
                        child: _SwipeLabel(
                          text: 'SKIP',
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _SwipeLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.2,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SwappTokens.spacingLg,
          vertical: SwappTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(SwappTokens.radiusMd),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}
