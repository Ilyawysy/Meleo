import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/id_generator.dart';
import '../models/checklist_item.dart';

class FocusChecklistItemDb {
  static final FocusChecklistItemDb _instance = FocusChecklistItemDb._internal();
  factory FocusChecklistItemDb() => _instance;
  FocusChecklistItemDb._internal();

  Future<Database> _getDb() async => DatabaseProvider().getDatabase();

  Future<List<ChecklistItem>> list(String taskId) async {
    final db = await _getDb();
    final rows = await db.query(
      'checklist_items',
      where: 'task_id = ? AND pending_delete = 0',
      whereArgs: [taskId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(_itemFromRow).toList();
  }

  Future<ChecklistItem> create(
    String taskId,
    String title,
    int sortOrder,
  ) async {
    final db = await _getDb();
    final now = DateTime.now();
    final id = generateLocalId();
    final row = <String, Object?>{
      'id': id,
      'task_id': taskId,
      'title': title,
      'is_done': 0,
      'sort_order': sortOrder,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'remote_id': null,
      'version': 0,
      'dirty': 1,
      'pending_delete': 0,
    };
    await db.insert(
      'checklist_items',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return _itemFromRow(row);
  }

  Future<ChecklistItem?> update(
    String id, {
    String? title,
    bool? isDone,
    int? sortOrder,
  }) async {
    final db = await _getDb();
    final values = <String, Object?>{};
    if (title != null) values['title'] = title;
    if (isDone != null) values['is_done'] = isDone ? 1 : 0;
    if (sortOrder != null) values['sort_order'] = sortOrder;
    values['updated_at'] = DateTime.now().toIso8601String();
    values['dirty'] = 1;

    await db.update(
      'checklist_items',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    final rows = await db.query(
      'checklist_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _itemFromRow(rows.first);
  }

  Future<void> delete(String id) async {
    final db = await _getDb();
    await db.update(
      'checklist_items',
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
    await db.delete('checklist_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> dirtyRows() async {
    final db = await _getDb();
    return db.query('checklist_items', where: 'dirty = 1');
  }

  Future<void> upsertFromRemote(ChecklistItem remote) async {
    final db = await _getDb();
    final existing = await db.query(
      'checklist_items',
      where: 'remote_id = ?',
      whereArgs: [remote.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final isDirty = (existing.first['dirty'] as int? ?? 0) == 1;
      if (isDirty) return;
    }

    final row = <String, Object?>{
      'id': existing.isNotEmpty ? existing.first['id'] as String : remote.id,
      'task_id': remote.taskId,
      'title': remote.title,
      'is_done': remote.isDone ? 1 : 0,
      'sort_order': remote.sortOrder,
      'created_at': remote.createdAt.toIso8601String(),
      'updated_at': remote.updatedAt.toIso8601String(),
      'remote_id': remote.id,
      'version': 0,
      'dirty': 0,
      'pending_delete': 0,
    };

    if (existing.isNotEmpty) {
      await db.update(
        'checklist_items',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id'] as String],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.insert(
        'checklist_items',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> setSynced(String localId, {required String remoteId}) async {
    final db = await _getDb();
    await db.update(
      'checklist_items',
      {
        'remote_id': remoteId,
        'dirty': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> setClean(String localId) async {
    final db = await _getDb();
    await db.update(
      'checklist_items',
      {'dirty': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  ChecklistItem _itemFromRow(Map<String, Object?> row) {
    return ChecklistItem(
      id: row['id'] as String,
      taskId: row['task_id'] as String,
      title: row['title'] as String,
      isDone: (row['is_done'] as int? ?? 0) == 1,
      sortOrder: row['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
