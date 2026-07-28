import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_provider.dart';
import '../models/task.dart';

class FocusTaskDb {
  static final FocusTaskDb _instance = FocusTaskDb._internal();
  factory FocusTaskDb() => _instance;
  FocusTaskDb._internal();

  Future<Database> _getDb() async => DatabaseProvider().getDatabase();

  Future<Task> create(Task task) async {
    final db = await _getDb();
    final row = <String, Object?>{
      ...task.toDb(),
      'remote_id': null,
      'dirty': 1,
      'pending_delete': 0,
    };
    await db.insert(
      'tasks',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return task;
  }

  Future<Task?> getById(String id) async {
    final db = await _getDb();
    final rows = await db.query(
      'tasks',
      where: 'id = ? AND pending_delete = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Task.fromDb(rows.first);
  }

  Future<List<Task>> listForRoom(String roomId) async {
    final db = await _getDb();
    final rows = await db.query(
      'tasks',
      where: 'room_id = ? AND pending_delete = 0',
      whereArgs: [roomId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(Task.fromDb).toList();
  }

  Future<Task> update(Task task) async {
    final db = await _getDb();
    final values = <String, Object?>{
      ...task.toDb(),
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await db.update(
      'tasks',
      values,
      where: 'id = ?',
      whereArgs: [task.id],
    );
    return task.copyWith(updatedAt: DateTime.now());
  }

  Future<void> softDelete(String id) async {
    final db = await _getDb();
    await db.update(
      'tasks',
      {
        'pending_delete': 1,
        'dirty': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteHard(String id) async {
    final db = await _getDb();
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markDirty(String id) async {
    final db = await _getDb();
    await db.update(
      'tasks',
      {'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markClean(String id) async {
    final db = await _getDb();
    await db.update(
      'tasks',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> listDirty() async {
    final db = await _getDb();
    return db.query('tasks', where: 'dirty = 1');
  }

  Future<void> setSynced(String localId, {required String remoteId}) async {
    final db = await _getDb();
    await db.update(
      'tasks',
      {
        'remote_id': remoteId,
        'dirty': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<String?> getRemoteId(String localId) async {
    final db = await _getDb();
    final rows = await db.query(
      'tasks',
      columns: ['remote_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['remote_id'] as String?;
  }

  /// Apply a task received from server during pull sync.
  /// Skips overwrite if local row is dirty (conservative conflict resolution).
  Future<bool> applyRemote(Task remote) async {
    final db = await _getDb();
    final existing = await db.query(
      'tasks',
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
        'tasks',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id'] as String],
      );
    } else {
      await db.insert(
        'tasks',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return true;
  }

  /// Hard-delete a task by remote_id (for deleted=true from sync).
  Future<void> deleteByRemoteIdHard(String remoteId) async {
    final db = await _getDb();
    await db.delete(
      'tasks',
      where: 'remote_id = ? OR id = ?',
      whereArgs: [remoteId, remoteId],
    );
  }
}
