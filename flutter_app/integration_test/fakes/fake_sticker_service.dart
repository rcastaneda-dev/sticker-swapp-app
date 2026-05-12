import 'package:flutter_app/features/stickers/data/models/sticker.dart';
import 'package:flutter_app/features/stickers/data/services/sticker_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixtures/test_stickers.dart';

/// Returns canned sticker data for integration tests.
class FakeStickerService extends StickerService {
  FakeStickerService()
      : super(
          client: SupabaseClient(
            'https://fake.supabase.co',
            'fake-anon-key',
            authOptions:
                const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<List<Sticker>> fetchStickers({String? team, String? type}) async {
    var result = testStickers.toList();
    if (team != null) {
      result = result.where((s) => s.team == team).toList();
    }
    if (type != null) {
      result = result.where((s) => s.type == type).toList();
    }
    return result;
  }

  @override
  Future<List<String>> fetchTeams() async {
    final teams = <String>{};
    for (final s in testStickers) {
      if (s.team != null) teams.add(s.team!);
    }
    return teams.toList()..sort();
  }
}
