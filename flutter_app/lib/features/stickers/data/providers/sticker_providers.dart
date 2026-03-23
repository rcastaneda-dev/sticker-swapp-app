import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sticker.dart';
import '../services/sticker_service.dart';

/// Provider for the StickerService singleton.
final stickerServiceProvider = Provider<StickerService>((ref) {
  return StickerService();
});

/// Current filter state for the sticker catalog.
class StickerFilter {
  final String? team;
  final String? type;

  const StickerFilter({this.team, this.type});

  StickerFilter copyWith({
    String? Function()? team,
    String? Function()? type,
  }) {
    return StickerFilter(
      team: team != null ? team() : this.team,
      type: type != null ? type() : this.type,
    );
  }
}

/// Notifier for managing catalog filter state.
class StickerFilterNotifier extends Notifier<StickerFilter> {
  @override
  StickerFilter build() => const StickerFilter();

  void setTeam(String? team) {
    state = state.copyWith(team: () => team);
  }

  void setType(String? type) {
    state = state.copyWith(type: () => type);
  }

  void clearAll() {
    state = const StickerFilter();
  }
}

final stickerFilterProvider =
    NotifierProvider<StickerFilterNotifier, StickerFilter>(
  StickerFilterNotifier.new,
);

/// Fetches stickers matching the current filter.
///
/// Re-fetches automatically when the filter changes via Riverpod dependency
/// tracking. The full result set is returned since even unfiltered (980 items)
/// fits in memory; the grid lazily renders only visible widgets.
final stickerListProvider = FutureProvider<List<Sticker>>((ref) {
  final filter = ref.watch(stickerFilterProvider);
  final service = ref.watch(stickerServiceProvider);
  return service.fetchStickers(team: filter.team, type: filter.type);
});

/// Fetches the distinct team list for the team filter picker.
final teamListProvider = FutureProvider<List<String>>((ref) {
  final service = ref.watch(stickerServiceProvider);
  return service.fetchTeams();
});
