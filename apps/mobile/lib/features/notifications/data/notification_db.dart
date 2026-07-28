import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_provider.dart';
import '../models/notification.dart';
import '../models/notification_mapper.dart';
import '../../../../core/id_generator.dart';

class NotificationDb {
  static final NotificationDb _instance = NotificationDb._internal();
  factory NotificationDb() => _instance;
  NotificationDb._internal();

  Future<Database> _getDb() async {
    return await DatabaseProvider().getDatabase();
  }

  Future<List<Notification>> list({int limit = 50, int offset = 0}) async {
    final db = await _getDb();
    final rows = await db.query(
      'notifications',
      where: 'pending_delete = 0',
      orderBy: 'time ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_notificationFromRow).toList();
  }

  Future<Notification> create({
    String? id,
    required String title,
    required DateTime time,
    String recurrence = 'none',
    bool sent = false,
  }) async {
    final db = await _getDb();
    final now = DateTime.now();
    final notificationId = id ?? generateLocalId();
    final row = <String, Object?>{
      'id': notificationId,
      'title': title,
      'time': time.toIso8601String(),
      'recurrence': recurrence,
      'sent': sent ? 1 : 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'remote_id': id, // Если ID передан, это remote_id
      'version': 0,
      'dirty': id == null ? 1 : 0, // Если ID передан с сервера, не помечаем как dirty
    };

    await db.insert(
      'notifications',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return _notificationFromRow(row);
  }

  Future<Notification> update(
    String id, {
    String? title,
    DateTime? time,
    String? recurrence,
    bool? sent,
  }) async {
    final db = await _getDb();
    final now = DateTime.now();

    final values = <String, Object?>{
      if (title != null) 'title': title,
      if (time != null) 'time': time.toIso8601String(),
      if (recurrence != null) 'recurrence': recurrence,
      if (sent != null) 'sent': sent ? 1 : 0,
      'updated_at': now.toIso8601String(),
      'dirty': 1,
    };

    Notification? result;
    await db.transaction((txn) async {
      await txn.update('notifications', values, where: 'id = ?', whereArgs: [id]);

      final rows = await txn.query(
        'notifications',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) {
        return;
      }

      result = _notificationFromRow(rows.first);
    });

    if (result == null) {
      return await create(
        title: title ?? 'Untitled',
        time: time ?? DateTime.now(),
        recurrence: recurrence ?? 'none',
      );
    }

    return result!;
  }

  Future<void> applyRemotePatch(String id, Map<String, Object?> values) async {
    final db = await _getDb();
    final patch = <String, Object?>{
      ...values,
      'updated_at': DateTime.now().toIso8601String(),
      'dirty': 0,
    };

    await db.update('notifications', patch, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _getDb();
    await db.update(
      'notifications',
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
    await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByRemoteIdHard(String remoteId) async {
    final db = await _getDb();
    await db.delete(
      'notifications',
      where: 'remote_id = ? OR id = ?',
      whereArgs: [remoteId, remoteId],
    );
  }

  Future<List<Map<String, Object?>>> dirtyRows() async {
    final db = await _getDb();
    return db.query('notifications', where: 'dirty = 1');
  }

  Future<bool> hasDirtyRows() async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM notifications WHERE dirty = 1) AS has_dirty',
    );
    return (result.first['has_dirty'] as int) == 1;
  }

  Future<void> setSynced(String localId, {required String remoteId}) async {
    final db = await _getDb();
    await db.update(
      'notifications',
      {
        'remote_id': remoteId,
        'dirty': 0,
        'version': (await _currentVersion(db, localId)) + 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> setClean(String localId) async {
    final db = await _getDb();
    await db.update(
      'notifications',
      {'dirty': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markAsSent(String id) async {
    final db = await _getDb();
    await db.update(
      'notifications',
      {
        'sent': 1,
        'updated_at': DateTime.now().toIso8601String(),
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> _currentVersion(Database db, String id) async {
    final rows = await db.query(
      'notifications',
      columns: ['version'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['version'] as int?) ?? 0;
  }

  Future<bool> upsertFromRemote(Notification remote) async {
    final db = await _getDb();

    final existing = await db.query(
      'notifications',
      where: 'remote_id = ?',
      whereArgs: [remote.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final isDirty = (existing.first['dirty'] as int? ?? 0) == 1;
      if (isDirty) {
        debugPrint(
          '⚠️ [NotificationSync] Conflict detected: notification ${remote.id} | '
          'local_updated_at=${existing.first['updated_at']}, '
          'remote_updated_at=${remote.updatedAt.toIso8601String()} | '
          'policy=conservative (keep_local, will_resolve_after_push)',
        );
        return false;
      }

      final existingUpdatedAtStr = existing.first['updated_at'] as String?;
      if (existingUpdatedAtStr == remote.updatedAt.toIso8601String()) {
        return false;
      }
    }

    final row = <String, Object?>{
      'id': (existing.isNotEmpty ? existing.first['id'] as String : remote.id),
      'title': remote.title,
      'time': remote.time.toIso8601String(),
      'recurrence': remote.recurrence.name,
      'sent': remote.sent ? 1 : 0,
      'created_at': remote.createdAt.toIso8601String(),
      'updated_at': remote.updatedAt.toIso8601String(),
      'remote_id': remote.id,
      'dirty': 0,
    };

    await db.transaction((txn) async {
      if (existing.isNotEmpty) {
        await txn.update(
          'notifications',
          row,
          where: 'id = ?',
          whereArgs: [existing.first['id'] as String],
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        await txn.insert(
          'notifications',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return true;
  }

  Notification _notificationFromRow(Map<String, Object?> row) {
    final map = <String, dynamic>{
      'id': row['id'] as String,
      'title': row['title'] as String,
      'time': row['time'] as String?,
      'recurrence': row['recurrence'] as String?,
      'created_at': row['created_at'] as String?,
      'updated_at': row['updated_at'] as String?,
    };
    final notification = notificationFromApiJson(map);
    // Добавляем поле sent из БД
    final sent = (row['sent'] as int? ?? 0) == 1;
    return notification.copyWith(sent: sent);
  }

  Future<Notification?> findByRemoteId(String remoteId) async {
    final db = await _getDb();
    final rows = await db.query(
      'notifications',
      where: 'remote_id = ? AND pending_delete = 0',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _notificationFromRow(rows.first);
  }

  Future<void> clearAll() async {
    await DatabaseProvider().clearAllOnLogout();
  }
}
