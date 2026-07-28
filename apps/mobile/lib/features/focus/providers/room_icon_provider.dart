import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/room_icon_db.dart';
import '../models/room_icon.dart';

final roomIconProvider =
    FutureProvider.family<RoomIcon?, String>((ref, roomId) async {
  final slug = await RoomIconDb().get(roomId);
  return RoomIconSlug.fromSlug(slug);
});

Future<void> setRoomIcon(WidgetRef ref, String roomId, RoomIcon icon) async {
  await RoomIconDb().set(roomId, icon.slug);
  ref.invalidate(roomIconProvider(roomId));
}
