import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for reading/writing the authenticated user's sticker inventory
/// from the Supabase `user_inventory` table.
class UserInventoryService {
  final SupabaseClient? _injectedClient;

  UserInventoryService({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Fetch the set of owned sticker IDs (OWNED or DUPLICATE status).
  Future<Set<int>> fetchOwnedStickerIds() async {
    final response = await _client
        .from('user_inventory')
        .select('sticker_id')
        .inFilter('status', ['OWNED', 'DUPLICATE']);
    return (response as List)
        .map((row) => row['sticker_id'] as int)
        .toSet();
  }

  /// Toggle a sticker's ownership status.
  ///
  /// If currently in inventory (OWNED/DUPLICATE) → delete the row.
  /// If not in inventory → insert as OWNED.
  Future<void> toggleSticker(int stickerId) async {
    final userId = _client.auth.currentUser!.id;
    final existing = await _client
        .from('user_inventory')
        .select('id, status')
        .eq('user_id', userId)
        .eq('sticker_id', stickerId)
        .maybeSingle();

    if (existing != null) {
      await _client.from('user_inventory').delete().eq('id', existing['id']);
    } else {
      await _client.from('user_inventory').insert({
        'user_id': userId,
        'sticker_id': stickerId,
        'status': 'OWNED',
        'quantity': 1,
      });
    }
  }

  /// Create a shareable wishlist link. Returns the share token.
  Future<String> createWishlistShare() async {
    final result = await _client.rpc('create_wishlist_share');
    final data = result as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to create wishlist share');
    }
    return data['token'] as String;
  }
}
