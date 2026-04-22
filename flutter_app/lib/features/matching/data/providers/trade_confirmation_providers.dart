import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_app/features/chat/data/providers/chat_providers.dart';
import 'package:flutter_app/features/matching/data/services/trade_confirmation_service.dart';

// ── State ────────────────────────────────────────────────────────────────

enum ConfirmationStatus {
  loading,
  idle,
  confirming,
  waitingForOther,
  completed,
  error,
}

class TradeConfirmationState {
  final ConfirmationStatus status;
  final bool callerConfirmed;
  final bool otherConfirmed;
  final String? errorMessage;

  const TradeConfirmationState({
    this.status = ConfirmationStatus.loading,
    this.callerConfirmed = false,
    this.otherConfirmed = false,
    this.errorMessage,
  });

  TradeConfirmationState copyWith({
    ConfirmationStatus? status,
    bool? callerConfirmed,
    bool? otherConfirmed,
    String? Function()? errorMessage,
  }) {
    return TradeConfirmationState(
      status: status ?? this.status,
      callerConfirmed: callerConfirmed ?? this.callerConfirmed,
      otherConfirmed: otherConfirmed ?? this.otherConfirmed,
      errorMessage:
          errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────

class TradeConfirmationNotifier extends Notifier<TradeConfirmationState> {
  final String _matchId;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  TradeConfirmationNotifier(this._matchId);

  @override
  TradeConfirmationState build() {
    ref.onDispose(() => _eventSubscription?.cancel());
    return const TradeConfirmationState();
  }

  /// Fetch initial state from backend and subscribe to real-time events.
  Future<void> initialize() async {
    final service = ref.read(tradeConfirmationServiceProvider);

    try {
      final result = await service.getConfirmationState(_matchId);
      state = _mapResultToState(result);
    } catch (e) {
      state = TradeConfirmationState(
        status: ConfirmationStatus.error,
        errorMessage: e.toString(),
      );
    }

    _subscribeToAblyEvents();
  }

  /// User taps "Mark as Done".
  Future<void> confirm() async {
    state = state.copyWith(status: ConfirmationStatus.confirming);

    final service = ref.read(tradeConfirmationServiceProvider);
    try {
      final result = await service.confirmTrade(_matchId);
      state = _mapResultToState(result);
    } catch (e) {
      state = state.copyWith(
        status: ConfirmationStatus.error,
        errorMessage: () => e.toString(),
      );
    }
  }

  void _subscribeToAblyEvents() {
    final ablyService = ref.read(ablyServiceProvider);
    final stream = ablyService.subscribeToEvent(_matchId, 'trade.confirmed');
    if (stream == null) return;

    _eventSubscription = stream.listen((data) {
      final bothConfirmed = data['both_confirmed'] == true;

      if (bothConfirmed) {
        state = state.copyWith(
          status: ConfirmationStatus.completed,
          callerConfirmed: true,
          otherConfirmed: true,
        );
      } else {
        // The other user confirmed (we already know our own state)
        state = state.copyWith(
          otherConfirmed: true,
          status: state.callerConfirmed
              ? ConfirmationStatus.completed
              : ConfirmationStatus.idle,
        );
      }
    }, onError: (e) {
      debugPrint('Ably trade.confirmed subscription error: $e');
    });
  }

  TradeConfirmationState _mapResultToState(TradeConfirmationResult result) {
    ConfirmationStatus status;
    if (result.bothConfirmed) {
      status = ConfirmationStatus.completed;
    } else if (result.callerConfirmed) {
      status = ConfirmationStatus.waitingForOther;
    } else {
      status = ConfirmationStatus.idle;
    }

    return TradeConfirmationState(
      status: status,
      callerConfirmed: result.callerConfirmed,
      otherConfirmed: result.otherConfirmed,
    );
  }
}

// ── Providers ────────────────────────────────────────────────────────────

final tradeConfirmationServiceProvider =
    Provider<TradeConfirmationService>((ref) {
  return TradeConfirmationService(
    baseUrl: const String.fromEnvironment('GO_SERVICE_URL'),
  );
});

final tradeConfirmationProvider = NotifierProvider.family<
    TradeConfirmationNotifier, TradeConfirmationState, String>(
  (matchId) => TradeConfirmationNotifier(matchId),
);
