import '../database/database_provider.dart';
import 'sync_versions_api.dart';

/// Persists server domain versions and sync cursor in the `sync_state` key-value table.
///
/// Keys: `domain_version_tasks`, `domain_version_notifications`, etc.
/// Cursor key: `sync_cursor`.
///
/// null return from [loadVersions] means first sync — all domains must be synced.
/// Versions and cursor are saved atomically in one transaction.
class SyncVersionStore {
  SyncVersionStore._();
  static final SyncVersionStore instance = SyncVersionStore._();

  static const _prefix = 'domain_version_';
  static const _cursorKey = 'sync_cursor';
  static const _keys = ['tasks', 'notifications', 'messages', 'focus', 'rhythm'];

  Future<DomainVersions?> loadVersions() async {
    final db = await DatabaseProvider().getDatabase();
    final rows = await db.query(
      'sync_state',
      where: 'key IN (?, ?, ?, ?, ?)',
      whereArgs: _keys.map((k) => '$_prefix$k').toList(),
    );

    if (rows.length < _keys.length) return null;

    final map = <String, int>{};
    for (final row in rows) {
      final key = (row['key'] as String).replaceFirst(_prefix, '');
      map[key] = int.tryParse(row['value'] as String? ?? '') ?? 0;
    }

    if (!_keys.every((k) => map.containsKey(k))) return null;

    return DomainVersions(
      tasks: map['tasks']!,
      notifications: map['notifications']!,
      messages: map['messages']!,
      focus: map['focus']!,
      rhythm: map['rhythm']!,
    );
  }

  Future<String?> loadCursor() async {
    final db = await DatabaseProvider().getDatabase();
    final rows = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: [_cursorKey],
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    return (value != null && value.isNotEmpty) ? value : null;
  }

  /// Save versions and cursor atomically in one transaction.
  Future<void> saveVersionsAndCursor(DomainVersions versions, String? cursor) async {
    final db = await DatabaseProvider().getDatabase();
    await db.transaction((txn) async {
      for (final entry in {
        'tasks': versions.tasks,
        'notifications': versions.notifications,
        'messages': versions.messages,
        'focus': versions.focus,
        'rhythm': versions.rhythm,
      }.entries) {
        await txn.rawInsert(
          'INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)',
          ['$_prefix${entry.key}', '${entry.value}'],
        );
      }
      if (cursor != null) {
        await txn.rawInsert(
          'INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)',
          [_cursorKey, cursor],
        );
      } else {
        await txn.delete(
          'sync_state',
          where: 'key = ?',
          whereArgs: [_cursorKey],
        );
      }
    });
  }

  Future<void> clear() async {
    final db = await DatabaseProvider().getDatabase();
    await db.delete(
      'sync_state',
      where: 'key LIKE ? OR key = ?',
      whereArgs: ['$_prefix%', _cursorKey],
    );
  }
}
