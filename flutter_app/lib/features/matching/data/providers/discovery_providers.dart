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
  final bool hasMore;
  final bool isLoadingMore;
  final int totalCount;

  const DiscoveryState({
    this.status = DiscoveryStatus.awaitingLocation,
    this.matches = const [],
    this.currentIndex = 0,
    this.lastSwipeResult,
    this.errorMessage,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.totalCount = 0,
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
    bool? hasMore,
    bool? isLoadingMore,
    int? totalCount,
  }) {
    return DiscoveryState(
      status: status ?? this.status,
      matches: matches ?? this.matches,
      currentIndex: currentIndex ?? this.currentIndex,
      lastSwipeResult:
          lastSwipeResult != null ? lastSwipeResult() : this.lastSwipeResult,
      errorMessage:
          errorMessage != null ? errorMessage() : this.errorMessage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}

/// Drives the discovery flow: location → fetch matches → swipe actions.
class DiscoveryNotifier extends Notifier<DiscoveryState> {
  static const _pageSize = 10;
  static const _prefetchThreshold = 3;

  @override
  DiscoveryState build() => const DiscoveryState();

  /// Request location permission + GPS, then fetch the first page.
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

    await _fetchMatches(offset: 0);
  }

  Future<void> _fetchMatches({required int offset}) async {
    if (offset == 0) {
      state = state.copyWith(status: DiscoveryStatus.loading);
    }

    try {
      final locationResult = ref.read(locationNotifierProvider).value;
      if (locationResult == null || !locationResult.success) {
        state = state.copyWith(
          status: DiscoveryStatus.error,
          errorMessage: () => 'Unable to determine your location.',
          isLoadingMore: false,
        );
        return;
      }

      final service = ref.read(matchDiscoveryServiceProvider);
      final page = await service.fetchMatches(
        latitude: locationResult.latitude!,
        longitude: locationResult.longitude!,
        offset: offset,
        limit: _pageSize,
      );

      final allMatches = offset == 0
          ? page.matches
          : [...state.matches, ...page.matches];
      final hasMore = offset + page.matches.length < page.totalCount;

      if (allMatches.isEmpty) {
        state = state.copyWith(
          status: DiscoveryStatus.empty,
          matches: [],
          currentIndex: 0,
          hasMore: false,
          isLoadingMore: false,
          totalCount: page.totalCount,
        );
      } else {
        state = state.copyWith(
          status: DiscoveryStatus.ready,
          matches: allMatches,
          currentIndex: offset == 0 ? 0 : state.currentIndex,
          hasMore: hasMore,
          isLoadingMore: false,
          totalCount: page.totalCount,
          lastSwipeResult: offset == 0 ? () => null : null,
        );
      }
    } on MatchDiscoveryException catch (e) {
      if (offset == 0) {
        state = state.copyWith(
          status: DiscoveryStatus.error,
          errorMessage: () => e.message,
          isLoadingMore: false,
        );
      } else {
        state = state.copyWith(isLoadingMore: false);
      }
    } catch (_) {
      if (offset == 0) {
        state = state.copyWith(
          status: DiscoveryStatus.error,
          errorMessage: () => 'Something went wrong. Please try again.',
          isLoadingMore: false,
        );
      } else {
        state = state.copyWith(isLoadingMore: false);
      }
    }
  }

  /// Fetch the next page of matches.
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);
    await _fetchMatches(offset: state.matches.length);
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
    final remaining = state.matches.length - nextIndex;

    // Prefetch when running low on cards.
    if (remaining <= _prefetchThreshold &&
        state.hasMore &&
        !state.isLoadingMore) {
      loadMore();
    }

    if (nextIndex >= state.matches.length && !state.hasMore) {
      state = state.copyWith(
        status: DiscoveryStatus.empty,
        currentIndex: nextIndex,
      );
    } else {
      state = state.copyWith(currentIndex: nextIndex);
    }
  }

  /// Re-fetch location and matches from the beginning.
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
