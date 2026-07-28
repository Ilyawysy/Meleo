import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_provider.dart';

class RoomIconDb {
  static final RoomIconDb _instance = RoomIconDb._internal();
  factory RoomIconDb() => _instance;
  RoomIconDb._internal();

  Future<String?> get(String roomId) async {
    final db = await DatabaseProvider().getDatabase();
    final rows = await db.query(
      'room_icons',
      columns: ['icon_slug'],
      where: 'room_id = ?',
      whereArgs: [roomId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['icon_slug'] as String?;
  }

  Future<void> set(String roomId, String slug) async {
    final db = await DatabaseProvider().getDatabase();
    await db.insert(
      'room_icons',
      {'room_id': roomId, 'icon_slug': slug},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clear(String roomId) async {
    final db = await DatabaseProvider().getDatabase();
    await db.delete('room_icons', where: 'room_id = ?', whereArgs: [roomId]);
  }

  Future<Map<String, String>> getAll(Iterable<String> roomIds) async {
    final ids = roomIds.toList();
    if (ids.isEmpty) return {};
    final db = await DatabaseProvider().getDatabase();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT room_id, icon_slug FROM room_icons WHERE room_id IN ($placeholders)',
      ids,
    );
    return {
      for (final row in rows)
        row['room_id'] as String: row['icon_slug'] as String,
    };
  }

  /// Removes icon records for rooms that no longer exist.
  ///
  /// Pass the IDs of rooms that currently exist; any row in room_icons
  /// whose room_id is not in this set will be deleted.
  ///
  /// Safety: if [existingRoomIds] is empty, this method is a no-op
  /// (prevents accidentally wiping all icons when the caller hasn't
  /// yet loaded rooms from sync).
  Future<void> clearOrphans(Iterable<String> existingRoomIds) async {
    final ids = existingRoomIds.toList();
    if (ids.isEmpty) return;
    final db = await DatabaseProvider().getDatabase();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawDelete(
      'DELETE FROM room_icons WHERE room_id NOT IN ($placeholders)',
      ids,
    );
  }
}
