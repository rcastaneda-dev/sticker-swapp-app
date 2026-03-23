import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sticker.dart';

/// Service for querying the sticker catalog from Supabase.
class StickerService {
  final SupabaseClient _client;

  StickerService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Fetch stickers with optional filters.
  ///
  /// All 980 stickers fit comfortably in memory; the grid lazily renders
  /// only visible items via SliverGrid builder delegate.
  Future<List<Sticker>> fetchStickers({
    String? team,
    String? type,
  }) async {
    var query = _client.from('stickers').select();

    if (team != null) {
      query = query.eq('team', team);
    }
    if (type != null) {
      query = query.eq('type', type);
    }

    final response = await query.order('sticker_number');
    return (response as List).map((row) => Sticker.fromJson(row)).toList();
  }

  /// Fetch distinct team names from the catalog.
  Future<List<String>> fetchTeams() async {
    final response = await _client
        .from('stickers')
        .select('team')
        .not('team', 'is', null)
        .order('team');

    final teams = <String>{};
    for (final row in response as List) {
      final team = row['team'] as String?;
      if (team != null) teams.add(team);
    }
    return teams.toList();
  }
}
