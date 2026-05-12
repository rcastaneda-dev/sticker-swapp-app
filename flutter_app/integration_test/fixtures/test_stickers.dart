import 'package:flutter_app/features/stickers/data/models/sticker.dart';

/// Small subset of the 980-sticker catalog for integration tests.
const testStickers = [
  Sticker(id: 1, stickerNumber: 1, title: 'Messi', team: 'Argentina', page: 1, type: 'player'),
  Sticker(id: 2, stickerNumber: 2, title: 'Neymar', team: 'Brazil', page: 2, type: 'player'),
  Sticker(id: 3, stickerNumber: 3, title: 'Mbappé', team: 'France', page: 3, type: 'player'),
  Sticker(id: 4, stickerNumber: 4, title: 'Salah', team: 'Egypt', page: 4, type: 'player'),
  Sticker(id: 5, stickerNumber: 5, title: 'Lewandowski', team: 'Poland', page: 5, type: 'player'),
  Sticker(id: 6, stickerNumber: 6, title: 'De Bruyne', team: 'Belgium', page: 6, type: 'player'),
  Sticker(id: 7, stickerNumber: 7, title: 'Modric', team: 'Croatia', page: 7, type: 'player'),
  Sticker(id: 8, stickerNumber: 8, title: 'Kane', team: 'England', page: 8, type: 'player'),
  Sticker(id: 9, stickerNumber: 9, title: 'Estadio Azteca', team: 'Mexico', page: 9, type: 'stadium'),
  Sticker(id: 10, stickerNumber: 10, title: 'MetLife Stadium', team: null, page: 10, type: 'stadium'),
  Sticker(id: 11, stickerNumber: 11, title: 'Pelé', team: 'Brazil', page: 11, type: 'legend'),
  Sticker(id: 12, stickerNumber: 12, title: 'Maradona', team: 'Argentina', page: 12, type: 'legend'),
];

/// IDs of stickers pre-seeded as guest inventory.
const guestOwnedStickerIds = {1, 3, 5};
