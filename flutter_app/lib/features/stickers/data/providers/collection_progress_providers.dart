import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sticker.dart';
import 'sticker_providers.dart';
import 'effective_inventory_providers.dart';

/// Fetches the full 980-sticker catalog (no filters).
///
/// Cached independently from [stickerListProvider] so the progress
/// screen always reflects the complete album regardless of catalog
/// filter state.
final allStickersProvider = FutureProvider<List<Sticker>>((ref) {
  final service = ref.watch(stickerServiceProvider);
  return service.fetchStickers();
});

/// Progress stats for a single team.
class TeamProgress {
  final String team;
  final int owned;
  final int total;

  const TeamProgress({
    required this.team,
    required this.owned,
    required this.total,
  });

  double get percentage => total > 0 ? owned / total : 0.0;
}

/// Computes per-team progress from the full sticker catalog and inventory.
///
/// Groups all stickers by team, counts owned vs total for each, and sorts
/// by completion percentage descending. Updates reactively when stickers
/// are toggled in the inventory (guest or authenticated).
final teamProgressProvider = Provider<List<TeamProgress>>((ref) {
  final allStickers = ref.watch(allStickersProvider).value;
  final ownedIds = ref.watch(effectiveInventoryProvider).value;

  if (allStickers == null || ownedIds == null) return [];

  // Group stickers by team
  final Map<String, List<Sticker>> byTeam = {};
  for (final sticker in allStickers) {
    final team = sticker.team ?? 'Special';
    (byTeam[team] ??= []).add(sticker);
  }

  // Build progress entries
  final entries = byTeam.entries.map((entry) {
    final owned = entry.value.where((s) => ownedIds.contains(s.id)).length;
    return TeamProgress(
      team: entry.key,
      owned: owned,
      total: entry.value.length,
    );
  }).toList();

  // Sort by completion percentage descending, then alphabetically
  entries.sort((a, b) {
    final cmp = b.percentage.compareTo(a.percentage);
    return cmp != 0 ? cmp : a.team.compareTo(b.team);
  });

  return entries;
});

/// Overall collection progress (owned count out of total sticker count).
final overallProgressProvider = Provider<({int owned, int total})>((ref) {
  final allStickers = ref.watch(allStickersProvider).value;
  final ownedIds = ref.watch(effectiveInventoryProvider).value;
  final total = allStickers?.length ?? 980;
  final owned = ownedIds?.length ?? 0;
  return (owned: owned, total: total);
});
