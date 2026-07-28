import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../../features/search/data/search_index_dao.dart';

/// Единый провайдер подключения к базе данных meleo.db
/// 
/// Управляет версией БД, миграциями и конфигурацией.
/// Все компоненты (TaskDb, ChatDb, SearchIndexDao) получают
/// Database через getDatabase(), а не открывают его самостоятельно.
class DatabaseProvider {
  static final DatabaseProvider _instance = DatabaseProvider._internal();
  factory DatabaseProvider() => _instance;
  DatabaseProvider._internal();

  Database? _db;
  static const int _currentVersion = 25;

  /// Получить подключение к базе данных
  Future<Database> getDatabase() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'meleo.db');
    _db = await openDatabase(
      path,
      version: _currentVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
      onOpen: _onOpen,
    );
    return _db!;
  }

  /// Инициализация при старте приложения
  Future<void> ensureInitialized() async {
    await getDatabase();
  }

  /// Конфигурация БД при каждом открытии
  /// 
  /// Критично: Включает PRAGMA foreign_keys = ON для гарантии работы
  /// ON DELETE CASCADE во всех операциях.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  /// Проверки при каждом открытии БД
  Future<void> _onOpen(Database db) async {
    // Защита от старых/битых установок без sync_state
    await _ensureSyncStateTable(db);
  }

  /// Создание БД с нуля
  Future<void> _onCreate(Database db, int version) async {
    // Новые таблицы (v23): focus_rooms + tasks (unified schema)
    await _createFocusRoomsTable(db);
    await _createTasksTable(db);

    // Создание таблицы checklist_items (версия 20)
    await _createChecklistItemsTable(db);

    // Создание таблиц чатов
    await _createChatTables(db);

    // Создание таблиц поиска (версия 5)
    await _createSearchTables(db);

    // Создание таблицы notifications (версия 7)
    await db.execute('''
CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  time TEXT NOT NULL,
  recurrence TEXT NOT NULL DEFAULT 'none',
  sent INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_id TEXT,
  version INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0
);
''');

    // Создание таблиц focus (версия 14, включая обновлённые схемы v23)
    await _createFocusTables(db);

    // Таблица состояния синхронизации (версия 12)
    await _ensureSyncStateTable(db);

    // Таблица иконок комнат (версия 24)
    await _createRoomIconsTable(db);
  }

  /// Миграции БД
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Safety: ensure columns exist; ignore if already added
    try {
      await db.execute(
        'ALTER TABLE tasks ADD COLUMN pending_delete INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}

    // Миграция v3 → v4: добавление таблиц чатов
    if (oldVersion < 4) {
      await _createChatTables(db);
    }

    // Миграция v4 → v5: добавление таблиц поиска
    if (oldVersion < 5) {
      await _createSearchTables(db);
      // Backfill через SearchIndexDao.rebuildAll() в транзакции
      try {
        final searchIndexDao = SearchIndexDao();
        await db.transaction((txn) async {
          await searchIndexDao.rebuildAll(txn);
        });
      } catch (e) {
        debugPrint('⚠️ [DatabaseProvider] Failed to rebuild search index during migration: $e');
        // Не прерываем миграцию, если backfill не удался
        // Индекс будет построен при первом изменении данных
      }
    }

    // Миграция v5 → v6: добавление полей group_id
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN group_id TEXT');
      } catch (_) {}
    }

    // Миграция v6 → v7: добавление таблицы notifications
    if (oldVersion < 7) {
      try {
        await db.execute('''
CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  time TEXT NOT NULL,
  recurrence TEXT NOT NULL DEFAULT 'none',
  sent INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_id TEXT,
  version INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0
);
''');
      } catch (_) {}
    }

    // Миграция v7 → v8: добавление колонки sent в notifications (если таблица уже существует без sent)
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE notifications ADD COLUMN sent INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }

    // Миграция v12 → v13: удаление таблицы notes и очистка search индекса
    if (oldVersion < 13) {
      await db.execute('DROP TABLE IF EXISTS notes');
      await db.delete(
        'search_docs',
        where: 'doc_type = ?',
        whereArgs: [1],
      );
      await db.delete(
        'search_trigrams',
        where: 'doc_type = ?',
        whereArgs: [1],
      );
    }

    // Миграция v13 → v14: добавление таблиц focus (сессии + кэш)
    if (oldVersion < 14) {
      await _createFocusTables(db);
    }

    if (oldVersion < 15) {
      await db.execute('''
CREATE TABLE IF NOT EXISTS focus_pending_purchases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  item_id TEXT,
  quantity INTEGER,
  created_at TEXT NOT NULL
);
''');
    }

    // Миграция v15 → v16: gamification v0.10.2
    if (oldVersion < 16) {
      await _migrateGamificationV102(db);
    }

    // Миграция v16 → v17: simplify focus states (9 → 5)
    if (oldVersion < 17) {
      await _migrateSimplifyFocusStates(db);
    }

    // Миграция v17 → v18: merge stopped into cancelled
    if (oldVersion < 18) {
      await _mergeStoppedIntoCancelled(db);
    }

    // Миграция v18 → v19: normalize session_day to YYYY-MM-DD
    if (oldVersion < 19) {
      await db.execute(
        "UPDATE focus_sessions SET session_day = SUBSTR(session_day, 1, 10) WHERE LENGTH(session_day) > 10",
      );
    }

    // Миграция v19 → v20: добавление plan_day, start_time, sort_order в tasks; таблица checklist_items
    if (oldVersion < 20) {
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN plan_day TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN start_time TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      await _createChecklistItemsTable(db);
    }

    // Миграция v20 → v21: удаление таблиц rhythm
    if (oldVersion < 21) {
      await db.execute('DROP TABLE IF EXISTS rhythm_assignment_dates;');
      await db.execute('DROP TABLE IF EXISTS rhythm_assignments;');
      await db.execute('DROP TABLE IF EXISTS rhythm_segments;');
      await db.execute('DROP TABLE IF EXISTS rhythm_templates;');
    }

    // Миграция v21 → v22: таблица focus_task_segments
    if (oldVersion < 22) {
      await _createFocusTaskSegmentsTable(db);
    }

    // Миграция v22 → v23: focus_rooms refactor
    // Drop and recreate tables affected by focus-rooms schema change.
    // Sync state is reset because the old composite cursor is invalid.
    if (oldVersion < 23) {
      await db.execute('DROP TABLE IF EXISTS focus_task_segments');
      await db.execute('DROP TABLE IF EXISTS checklist_items');
      await db.execute('DROP TABLE IF EXISTS focus_sessions');
      await db.execute('DROP TABLE IF EXISTS focus_room_tasks');
      await db.execute('DROP TABLE IF EXISTS tasks');
      // Remove stale task search docs
      try {
        await db.execute("DELETE FROM search_docs WHERE doc_type = 0");
        await db.execute("DELETE FROM search_trigrams WHERE doc_type = 0");
      } catch (_) {}
      // Reset sync state — old composite cursor invalid after schema change
      await db.execute('DELETE FROM sync_state');
      // New tables
      await _createFocusRoomsTable(db);
      await _createTasksTable(db);
      await _createChecklistItemsTable(db);
      await _createFocusSessionsTable(db);
      await _createFocusTaskSegmentsTable(db);
    }

    // Миграция v23 → v24: room_icons table
    if (oldVersion < 24) {
      await _createRoomIconsTable(db);
    }

    if (oldVersion < 25) {
      try {
        await db.execute(
          'ALTER TABLE focus_rooms ADD COLUMN focus_duration_min INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE focus_rooms ADD COLUMN break_min INTEGER',
        );
      } catch (_) {}
    }
  }

  /// Создание таблиц чатов
  Future<void> _createChatTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS chat_threads (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_id TEXT,
  version INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  text TEXT NOT NULL,
  is_me INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  remote_id TEXT,
  order_index INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE
);
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_thread_id ON chat_messages(thread_id);',
    );
  }

  /// Создание таблиц поиска (версия 5)
  Future<void> _createSearchTables(Database db) async {
    // Таблица нормализованных документов
    await db.execute('''
CREATE TABLE IF NOT EXISTS search_docs (
  doc_type INTEGER NOT NULL,
  doc_id TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  norm_title TEXT NOT NULL,
  norm_body TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (doc_type, doc_id)
);
''');

    // Таблица триграмм (инвертированный индекс)
    await db.execute('''
CREATE TABLE IF NOT EXISTS search_trigrams (
  doc_type INTEGER NOT NULL,
  doc_id TEXT NOT NULL,
  trigram TEXT NOT NULL,
  field INTEGER NOT NULL,
  PRIMARY KEY (doc_type, doc_id, trigram, field),
  FOREIGN KEY (doc_type, doc_id) REFERENCES search_docs(doc_type, doc_id) ON DELETE CASCADE
);
''');

    // Индексы для производительности
    // Индекс для поиска с учётом типа документа
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_search_trigrams_trigram ON search_trigrams(trigram, doc_type);',
    );
    // Индекс для удаления триграмм документа
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_search_trigrams_doc ON search_trigrams(doc_type, doc_id);',
    );
  }

  /// Создание таблиц focus (версия 14+)
  Future<void> _createFocusTables(Database db) async {
    await _createFocusSessionsTable(db);

    await db.execute('''
CREATE TABLE IF NOT EXISTS focus_cache (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS focus_pending_purchases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  item_id TEXT,
  quantity INTEGER,
  created_at TEXT NOT NULL
);
''');

    await _createFocusTaskSegmentsTable(db);
  }

  /// focus_sessions table with room_id NOT NULL (v23+)
  Future<void> _createFocusSessionsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS focus_sessions (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL DEFAULT '',
  planned_duration_sec INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'created',
  active_elapsed_sec INTEGER NOT NULL DEFAULT 0,
  last_state_change_at TEXT,
  started_at TEXT,
  ended_at TEXT,
  task_id TEXT,
  earned_coins REAL NOT NULL DEFAULT 0.0,
  credited_minutes INTEGER,
  earned_xp INTEGER NOT NULL DEFAULT 0,
  session_day TEXT,
  undo_deadline_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_id TEXT,
  version INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0,
  pending_actions TEXT NOT NULL DEFAULT '[]'
);
''');
  }

  /// focus_rooms table (v23)
  Future<void> _createFocusRoomsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS focus_rooms (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#6366F1',
  type TEXT NOT NULL DEFAULT 'regular',
  archived INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  sprint_goal TEXT,
  sprint_deadline TEXT,
  sprint_total_hours INTEGER,
  focus_duration_min INTEGER,
  break_min INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_id TEXT,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_focus_rooms_archived ON focus_rooms(archived);',
    );
  }

  /// room_icons table (v24)
  Future<void> _createRoomIconsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS room_icons (
  room_id TEXT PRIMARY KEY,
  icon_slug TEXT NOT NULL
);
''');
  }

  /// tasks table — unified simplified Task schema (v23+)
  Future<void> _createTasksTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL,
  user_id TEXT,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'not_done',
  sort_order INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  deleted INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_id TEXT,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (room_id) REFERENCES focus_rooms(id) ON DELETE CASCADE
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_room ON tasks(room_id, sort_order);',
    );
  }

  Future<void> _createFocusTaskSegmentsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS focus_task_segments (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES focus_sessions(id) ON DELETE CASCADE
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_focus_task_segments_session ON focus_task_segments(session_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_focus_task_segments_task ON focus_task_segments(task_id);',
    );
  }

  /// Создание таблицы checklist_items (версия 20)
  Future<void> _createChecklistItemsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS checklist_items (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  title TEXT NOT NULL,
  is_done INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  remote_id TEXT,
  version INTEGER NOT NULL DEFAULT 0,
  dirty INTEGER NOT NULL DEFAULT 1,
  pending_delete INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_checklist_items_task_id ON checklist_items(task_id);',
    );
  }

  /// Миграция v15 → v16: gamification v0.10.2
  /// - Add session_day and undo_deadline_at to focus_sessions
  /// - Convert awaiting_confirm → stopped_pending_credit
  /// - Clear focus_cache (profile schema changed)
  /// - Delete pending freeze purchases
  Future<void> _migrateGamificationV102(Database db) async {
    // 1. Add new columns to focus_sessions
    try {
      await db.execute(
        'ALTER TABLE focus_sessions ADD COLUMN session_day TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE focus_sessions ADD COLUMN undo_deadline_at TEXT',
      );
    } catch (_) {}

    // 2. Convert old statuses to new ones
    await db.execute(
      "UPDATE focus_sessions SET status = 'stopped_pending_credit' WHERE status = 'awaiting_confirm'",
    );
    // completed sessions with credited_minutes > 0 → credited_final
    await db.execute(
      "UPDATE focus_sessions SET status = 'credited_final' WHERE status = 'completed' AND credited_minutes IS NOT NULL AND credited_minutes > 0",
    );
    // completed sessions with no credit → cancelled
    await db.execute(
      "UPDATE focus_sessions SET status = 'cancelled' WHERE status = 'completed' AND (credited_minutes IS NULL OR credited_minutes = 0)",
    );

    // 3. Clear focus_cache (profile schema changed completely)
    await db.delete('focus_cache');

    // 4. Delete pending freeze purchases (freeze mechanic removed)
    await db.execute(
      "DELETE FROM focus_pending_purchases WHERE type = 'freeze'",
    );
  }

  /// Миграция v16 → v17: simplify focus states (9 → 5)
  /// Map old statuses to new ones, clear undo_deadline_at, remove obsolete pending_actions
  Future<void> _migrateSimplifyFocusStates(Database db) async {
    // 1. Map old statuses to new ones
    await db.execute(
      "UPDATE focus_sessions SET status = 'finished' "
      "WHERE status IN ('stopped_pending_credit', 'credited_undoable', 'credited_final')",
    );
    await db.execute(
      "UPDATE focus_sessions SET status = 'cancelled' "
      "WHERE status IN ('paused', 'awaiting_confirm', 'completed')",
    );

    // 2. Clear undo_deadline_at
    await db.execute(
      "UPDATE focus_sessions SET undo_deadline_at = NULL WHERE undo_deadline_at IS NOT NULL",
    );

    // 3. Remove obsolete pending_actions (credit/undo/finalize/confirm/pause)
    final rows = await db.query(
      'focus_sessions',
      columns: ['id', 'pending_actions'],
      where: "pending_actions != '[]'",
    );
    const validActions = {'play', 'pause', 'finish', 'cancel', 'update_task'};
    for (final row in rows) {
      final localId = row['id'] as String;
      final actionsJson = row['pending_actions'] as String? ?? '[]';
      try {
        final parsed = json.decode(actionsJson) as List<dynamic>;
        final filtered = parsed.where((a) {
          if (a is Map<String, dynamic>) {
            return validActions.contains(a['action'] as String?);
          }
          return false;
        }).toList();
        if (filtered.length != parsed.length) {
          await db.update(
            'focus_sessions',
            {
              'pending_actions': json.encode(filtered),
              'dirty': filtered.isNotEmpty ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
        }
      } catch (e) {
        debugPrint('⚠️ [DatabaseProvider] Error cleaning pending_actions for $localId: $e');
      }
    }

    // 4. Clear focus_cache (profile/balance may have stale data)
    await db.delete('focus_cache');
  }

  /// Миграция v17 → v18: merge stopped into cancelled
  Future<void> _mergeStoppedIntoCancelled(Database db) async {
    await db.execute(
      "UPDATE focus_sessions SET status = 'cancelled' WHERE status = 'stopped'",
    );
  }

  Future<void> _ensureSyncStateTable(Database db) async {
    try {
      await db.execute('''
CREATE TABLE IF NOT EXISTS sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''');

      // Инициализируем курсор как null (оба значения отсутствуют = начало синхронизации)
      // Не создаём записи здесь - они будут созданы при первой синхронизации
    } catch (e) {
      debugPrint('⚠️ [DatabaseProvider] Error creating sync_state table: $e');
    }
  }

  /// Проверка включения PRAGMA foreign_keys (debug-only)
  /// 
  /// Возвращает true, если foreign_keys включены, иначе false.
  /// Логирует предупреждение, если foreign_keys выключены.
  Future<bool> verifyForeignKeys() async {
    final db = await getDatabase();
    final result = await db.rawQuery('PRAGMA foreign_keys;');
    final enabled = (result.first['foreign_keys'] as int?) == 1;
    if (!enabled) {
      debugPrint('⚠️ [DatabaseProvider] PRAGMA foreign_keys is OFF! Expected: ON');
    }
    return enabled;
  }

  /// Единая точка очистки при logout
  /// 
  /// Критично: Все очистки выполняются атомарно в одной транзакции.
  /// Rhythm данные НЕ очищаются при logout - они локальные и не синхронизируются
  Future<void> clearAllOnLogout() async {
    final db = await getDatabase();
    await db.transaction((txn) async {
      await txn.delete('checklist_items');
      await txn.delete('tasks');
      await txn.delete('focus_rooms');
      await txn.delete('chat_messages');
      await txn.delete('chat_threads');
      await txn.delete('notifications');
      await txn.delete('focus_task_segments');
      await txn.delete('focus_sessions');
      await txn.delete('focus_cache');
      await txn.delete('focus_pending_purchases');
      await txn.delete('search_docs');
      await txn.delete('search_trigrams');
      await txn.delete('room_icons');
      await txn.delete('sync_state');
    });
    debugPrint('All data cleared from local database');
  }
}

