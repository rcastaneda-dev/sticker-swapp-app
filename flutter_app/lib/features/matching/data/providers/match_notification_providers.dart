import 'package:flutter_riverpod/flutter_riverpod.dart';

class UnviewedMatch {
  final String matchId;
  final String displayName;

  const UnviewedMatch({required this.matchId, required this.displayName});
}

class MatchNotificationNotifier extends Notifier<List<UnviewedMatch>> {
  @override
  List<UnviewedMatch> build() => [];

  void addMatch(UnviewedMatch match) {
    state = [...state, match];
  }

  void markViewed(String matchId) {
    state = state.where((m) => m.matchId != matchId).toList();
  }

  void clear() {
    state = [];
  }
}

final matchNotificationProvider =
    NotifierProvider<MatchNotificationNotifier, List<UnviewedMatch>>(
  MatchNotificationNotifier.new,
);

final unviewedMatchCountProvider = Provider<int>((ref) {
  return ref.watch(matchNotificationProvider).length;
});

final mostRecentUnviewedMatchProvider = Provider<UnviewedMatch?>((ref) {
  final matches = ref.watch(matchNotificationProvider);
  return matches.isNotEmpty ? matches.last : null;
});
