import 'package:flutter_app/features/matching/data/providers/trade_confirmation_providers.dart';

/// Controllable trade confirmation notifier for integration tests.
class FakeTradeConfirmationNotifier extends TradeConfirmationNotifier {
  final TradeConfirmationState _initial;
  bool initializeCalled = false;
  bool confirmCalled = false;

  FakeTradeConfirmationNotifier(
    super.matchId, [
    TradeConfirmationState? initial,
  ]) : _initial = initial ??
            const TradeConfirmationState(
              status: ConfirmationStatus.idle,
            );

  @override
  TradeConfirmationState build() => _initial;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    state = _initial;
  }

  @override
  Future<void> confirm() async {
    confirmCalled = true;
    state = state.copyWith(
      status: ConfirmationStatus.waitingForOther,
      callerConfirmed: true,
    );
  }

  /// Simulate the partner confirming (via Ably event).
  void simulatePartnerConfirmed() {
    state = state.copyWith(
      status: ConfirmationStatus.completed,
      callerConfirmed: true,
      otherConfirmed: true,
    );
  }
}
