import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scored_match.dart';
import '../models/swipe_result.dart';
import '../services/match_discovery_service.dart';
import 'location_providers.dart';

/// Singleton [MatchDiscoveryService] provider.
final matchDiscoveryServiceProvider = Provider<MatchDiscoveryService>((ref) {
  return MatchDiscoveryService(
    baseUrl: const String.fromEnvironment('GO_SERVICE_URL'),
  );
});

/// Current status of the discovery card stack.
enum DiscoveryStatus {
  awaitingLocation,
  loading,
  ready,
  empty,
  error,
}

/// Immutable state for the discovery flow.
class DiscoveryState {
  final DiscoveryStatus status;
  final List<ScoredMatch> matches;
  final int currentIndex;
  final SwipeResult? lastSwipeResult;
  final String? errorMessage;

  const DiscoveryState({
    this.status = DiscoveryStatus.awaitingLocation,
    this.matches = const [],
    this.currentIndex = 0,
    this.lastSwipeResult,
    this.errorMessage,
  });

  /// The match currently shown as the top card, or `null` if exhausted.
  ScoredMatch? get currentMatch =>
      currentIndex < matches.length ? matches[currentIndex] : null;

  /// Number of cards remaining (including current).
  int get remainingCount =>
      matches.length > currentIndex ? matches.length - currentIndex : 0;

  /// The next 1-2 matches behind the top card (for the stack visual).
  List<ScoredMatch> get upcomingMatches {
    final start = currentIndex + 1;
    final end = (currentIndex + 3).clamp(0, matches.length);
    if (start >= matches.length) return [];
    return matches.sublist(start, end);
  }

  DiscoveryState copyWith({
    DiscoveryStatus? status,
    List<ScoredMatch>? matches,
    int? currentIndex,
    SwipeResult? Function()? lastSwipeResult,
    String? Function()? errorMessage,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      matches: matches ?? this.matches,
      currentIndex: currentIndex ?? this.currentIndex,
      lastSwipeResult:
          lastSwipeResult != null ? lastSwipeResult() : this.lastSwipeResult,
      errorMessage:
          errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

/// Drives the discovery flow: location → fetch matches → swipe actions.
class DiscoveryNotifier extends Notifier<DiscoveryState> {
  @override
  DiscoveryState build() => const DiscoveryState();

  /// Request location permission + GPS, then fetch matches.
  Future<void> initialize() async {
    state = state.copyWith(status: DiscoveryStatus.awaitingLocation);

    final locationNotifier = ref.read(locationNotifierProvider.notifier);
    final permissionResult = await locationNotifier.requestAndUpdate();

    if (permissionResult != null) {
      state = state.copyWith(
        status: DiscoveryStatus.error,
        errorMessage: () =>
            'Location permission is required to discover nearby traders.',
      );
      return;
    }

    await _fetchMatches();
  }

  Future<void> _fetchMatches() async {
    state = state.copyWith(status: DiscoveryStatus.loading);

    try {
      final locationResult = ref.read(locationNotifierProvider).value;
      if (locationResult == null || !locationResult.success) {
        state = state.copyWith(
          status: DiscoveryStatus.error,
          errorMessage: () => 'Unable to determine your location.',
        );
        return;
      }

      final service = ref.read(matchDiscoveryServiceProvider);
      final matches = await service.fetchMatches(
        latitude: locationResult.latitude!,
        longitude: locationResult.longitude!,
      );

      if (matches.isEmpty) {
        state = state.copyWith(
          status: DiscoveryStatus.empty,
          matches: [],
          currentIndex: 0,
        );
      } else {
        state = state.copyWith(
          status: DiscoveryStatus.ready,
          matches: matches,
          currentIndex: 0,
          lastSwipeResult: () => null,
        );
      }
    } on MatchDiscoveryException catch (e) {
      state = state.copyWith(
        status: DiscoveryStatus.error,
        errorMessage: () => e.message,
      );
    } catch (_) {
      state = state.copyWith(
        status: DiscoveryStatus.error,
        errorMessage: () => 'Something went wrong. Please try again.',
      );
    }
  }

  /// Record a right-swipe, advance card, and return the result.
  Future<SwipeResult?> swipeRight() async {
    final match = state.currentMatch;
    if (match == null) return null;

    try {
      final service = ref.read(matchDiscoveryServiceProvider);
      final result = await service.swipeRight(match.userId);

      _advanceCard();
      state = state.copyWith(lastSwipeResult: () => result);
      return result;
    } catch (_) {
      // Advance even on error — don't block the swipe UX.
      _advanceCard();
      return null;
    }
  }

  /// Skip this card (no API call).
  void swipeLeft() {
    _advanceCard();
  }

  void _advanceCard() {
    final nextIndex = state.currentIndex + 1;
    if (nextIndex >= state.matches.length) {
      state = state.copyWith(
        status: DiscoveryStatus.empty,
        currentIndex: nextIndex,
      );
    } else {
      state = state.copyWith(currentIndex: nextIndex);
    }
  }

  /// Re-fetch location and matches.
  Future<void> refresh() async {
    await initialize();
  }

  /// Dismiss the mutual-match celebration overlay.
  void clearLastSwipeResult() {
    state = state.copyWith(lastSwipeResult: () => null);
  }
}

final discoveryProvider =
    NotifierProvider<DiscoveryNotifier, DiscoveryState>(DiscoveryNotifier.new);
