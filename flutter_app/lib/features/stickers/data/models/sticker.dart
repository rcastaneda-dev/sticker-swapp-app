/// Data model for a sticker from the `stickers` catalog table.
class Sticker {
  final int id;
  final int stickerNumber;
  final String title;
  final String? team;
  final int page;
  final String type; // 'player', 'stadium', 'legend'
  final String? imageUrl;

  const Sticker({
    required this.id,
    required this.stickerNumber,
    required this.title,
    this.team,
    required this.page,
    required this.type,
    this.imageUrl,
  });

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(
      id: json['id'] as int,
      stickerNumber: json['sticker_number'] as int,
      title: json['title'] as String,
      team: json['team'] as String?,
      page: json['page'] as int,
      type: json['type'] as String,
      imageUrl: json['image_url'] as String?,
    );
  }
}
