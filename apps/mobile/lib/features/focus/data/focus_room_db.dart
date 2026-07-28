import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_provider.dart';
import '../models/focus_room.dart';

class FocusRoomDb {
  static final FocusRoomDb _instance = FocusRoomDb._internal();
  factory FocusRoomDb() => _instance;
  FocusRoomDb._internal();

  Future<Database> _getDb() async => DatabaseProvider().getDatabase();

  Future<FocusRoom> create(FocusRoom room) async {
    final db = await _getDb();
    final row = <String, Object?>{
      ...room.toDb(),
      'remote_id': null,
      'dirty': 1,
      'pending_delete': 0,
    };
    await db.insert(
      'focus_rooms',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return room;
  }

  Future<FocusRoom?> getById(String id) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_rooms',
      where: 'id = ? AND pending_delete = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FocusRoom.fromDb(rows.first);
  }

  Future<List<FocusRoom>> listForUser({bool archived = false}) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_rooms',
      where: 'archived = ? AND pending_delete = 0',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(FocusRoom.fromDb).toList();
  }

  Future<FocusRoom> update(FocusRoom room) async {
    final db = await _getDb();
    final values = <String, Object?>{
      ...room.toDb(),
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await db.update(
      'focus_rooms',
      values,
      where: 'id = ?',
      whereArgs: [room.id],
    );
    return room.copyWith(updatedAt: DateTime.now());
  }

  Future<void> archive(String id) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();
    await db.update(
      'focus_rooms',
      {
        'archived': 1,
        'archived_at': now,
        'updated_at': now,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> unarchive(String id) async {
    final db = await _getDb();
    await db.update(
      'focus_rooms',
      {
        'archived': 0,
        'archived_at': null,
        'updated_at': DateTime.now().toIso8601String(),
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markDirty(String id) async {
    final db = await _getDb();
    await db.update(
      'focus_rooms',
      {'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markClean(String id) async {
    final db = await _getDb();
    await db.update(
      'focus_rooms',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> listDirty() async {
    final db = await _getDb();
    return db.query('focus_rooms', where: 'dirty = 1');
  }

  Future<void> setSynced(String localId, {required String remoteId}) async {
    final db = await _getDb();
    await db.update(
      'focus_rooms',
      {
        'remote_id': remoteId,
        'dirty': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Apply a room received from server during pull sync.
  /// Skips overwrite if local row is dirty (conservative conflict resolution).
  Future<bool> applyRemote(FocusRoom remote) async {
    final db = await _getDb();
    final existing = await db.query(
      'focus_rooms',
      where: 'remote_id = ?',
      whereArgs: [remote.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final isDirty = (existing.first['dirty'] as int? ?? 0) == 1;
      if (isDirty) return false;

      final existingUpdatedAt = existing.first['updated_at'] as String?;
      if (existingUpdatedAt == remote.updatedAt.toIso8601String()) return false;
    }

    final row = <String, Object?>{
      'id': existing.isNotEmpty ? existing.first['id'] as String : remote.id,
      ...remote.toDb(),
      'remote_id': remote.id,
      'dirty': 0,
      'pending_delete': 0,
    };

    if (existing.isNotEmpty) {
      await db.update(
        'focus_rooms',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id'] as String],
      );
    } else {
      await db.insert(
        'focus_rooms',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return true;
  }

  Future<int> getTaskCount(String roomId) async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM tasks WHERE room_id = ? AND pending_delete = 0',
      [roomId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<int> getTotalFocusSec(String roomId) async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(active_elapsed_sec), 0) as total '
      "FROM focus_sessions WHERE room_id = ? AND status = 'finished'",
      [roomId],
    );
    return (result.first['total'] as int?) ?? 0;
  }
}
