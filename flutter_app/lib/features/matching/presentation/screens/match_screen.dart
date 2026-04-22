import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/matching/data/providers/match_notification_providers.dart';
import 'package:flutter_app/features/matching/data/providers/trade_confirmation_providers.dart';
import 'package:flutter_app/shared/shared.dart';

class MatchScreen extends ConsumerStatefulWidget {
  final String matchId;

  const MatchScreen({super.key, required this.matchId});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  TradeConfirmationNotifier? _confirmationNotifier;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(matchNotificationProvider.notifier)
          .markViewed(widget.matchId);

      _confirmationNotifier =
          ref.read(tradeConfirmationProvider(widget.matchId).notifier);
      _confirmationNotifier!.initialize();
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUnder13 = ref.watch(isUnder13Provider) ?? false;

    if (isUnder13) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trade Match')),
        body: const SwappRestrictedEmptyState(
          icon: Icons.swap_horiz,
          title: 'Trading Not Available',
          subtitle:
              'Real-time trading is available for users 13 and older. '
              'You can manage your wishlist from your collection.',
        ),
      );
    }

    final confirmState =
        ref.watch(tradeConfirmationProvider(widget.matchId));

    return Scaffold(
      appBar: AppBar(title: const Text('Trade Match')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SwappTokens.spacingLg),
          child: Column(
            children: [
              _ConfirmationCard(
                state: confirmState,
                onConfirm: _initialized
                    ? () => _confirmationNotifier?.confirm()
                    : null,
              ),
              const SizedBox(height: SwappTokens.spacingLg),
              SwappButton(
                label: 'Open Chat',
                variant: SwappButtonVariant.secondary,
                icon: Icons.chat_bubble_outline,
                isExpanded: true,
                onPressed: () {
                  context.goNamed(
                    'chat',
                    pathParameters: {'matchId': widget.matchId},
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  final TradeConfirmationState state;
  final VoidCallback? onConfirm;

  const _ConfirmationCard({required this.state, this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SwappCard(
      variant: SwappCardVariant.elevated,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 48,
            color: colors.secondary,
          ),
          const SizedBox(height: SwappTokens.spacingSm),
          Text(
            'Trade Confirmation',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: SwappTokens.spacingXs),
          Text(
            'Both traders must confirm to complete',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SwappTokens.spacingLg),
          _buildStatusRow(context),
          const SizedBox(height: SwappTokens.spacingLg),
          _buildActionArea(context),
        ],
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ConfirmationChip(
          label: 'You',
          confirmed: state.callerConfirmed,
        ),
        const SizedBox(width: SwappTokens.spacingMd),
        _ConfirmationChip(
          label: 'Partner',
          confirmed: state.otherConfirmed,
        ),
      ],
    );
  }

  Widget _buildActionArea(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    switch (state.status) {
      case ConfirmationStatus.loading:
        return const SizedBox(
          height: 44,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );

      case ConfirmationStatus.idle:
        return SwappButton(
          label: 'Mark as Done',
          isExpanded: true,
          onPressed: onConfirm,
        );

      case ConfirmationStatus.confirming:
        return SwappButton(
          label: 'Mark as Done',
          isExpanded: true,
          isLoading: true,
          onPressed: null,
        );

      case ConfirmationStatus.waitingForOther:
        return SwappButton(
          label: 'Waiting for partner...',
          variant: SwappButtonVariant.outlined,
          icon: Icons.hourglass_top,
          isExpanded: true,
          onPressed: null,
        );

      case ConfirmationStatus.completed:
        return _CompletedIndicator();

      case ConfirmationStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.errorMessage ?? 'Something went wrong',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SwappTokens.spacingSm),
            SwappButton(
              label: 'Retry',
              variant: SwappButtonVariant.outlined,
              isExpanded: true,
              onPressed: onConfirm,
            ),
          ],
        );
    }
  }
}

class _ConfirmationChip extends StatelessWidget {
  final String label;
  final bool confirmed;

  const _ConfirmationChip({required this.label, required this.confirmed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingMd,
        vertical: SwappTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: confirmed
            ? colors.tertiaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            confirmed ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: confirmed ? colors.tertiary : colors.outline,
          ),
          const SizedBox(width: SwappTokens.spacingXs),
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: confirmed ? colors.onTertiaryContainer : colors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedIndicator extends StatefulWidget {
  @override
  State<_CompletedIndicator> createState() => _CompletedIndicatorState();
}

class _CompletedIndicatorState extends State<_CompletedIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
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
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: Icon(
            Icons.check_circle,
            size: 48,
            color: colors.tertiary,
          ),
        ),
        const SizedBox(height: SwappTokens.spacingSm),
        Text(
          'Trade Complete!',
          style: textTheme.titleMedium?.copyWith(
            color: colors.tertiary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
