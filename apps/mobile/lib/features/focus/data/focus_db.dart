import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/id_generator.dart';
import 'gamification_calculator.dart' as calc;
import '../models/focus_models.dart';
import '../models/gamification_models.dart';

class FocusDb {
  static final FocusDb _instance = FocusDb._internal();
  factory FocusDb() => _instance;
  FocusDb._internal();

  Future<Database> _getDb() async {
    return await DatabaseProvider().getDatabase();
  }

  // ---------------------------------------------------------------------------
  // Session methods
  // ---------------------------------------------------------------------------

  /// Create a new session locally (no server call). Sync service will push and set remote_id.
  Future<FocusSession> createSessionLocally({
    required int plannedDurationSec,
    String roomId = '',
    String? taskId,
  }) async {
    final existing = await getActiveSession();
    if (existing != null) {
      throw StateError('Cannot create session: active session ${existing.id} already exists');
    }
    final db = await _getDb();
    final now = DateTime.now();
    final nowStr = now.toIso8601String();
    final localId = generateLocalId();
    final sessionDay = calc.focusDate(now, 'UTC', calc.defaultDayCutoffHour);
    final row = <String, Object?>{
      'id': localId,
      'room_id': roomId,
      'planned_duration_sec': plannedDurationSec,
      'status': 'created',
      'active_elapsed_sec': 0,
      'last_state_change_at': null,
      'started_at': null,
      'ended_at': null,
      'task_id': taskId,
      'earned_coins': 0.0,
      'credited_minutes': null,
      'earned_xp': 0,
      'session_day': sessionDay.toIso8601String().substring(0, 10),
      'created_at': nowStr,
      'updated_at': nowStr,
      'remote_id': null,
      'version': 0,
      'dirty': 0,  // local-only until Play; orchestrator won't touch it
      'pending_delete': 0,
      'pending_actions': '[]',
    };
    await db.insert(
      'focus_sessions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return _sessionFromRow(row);
  }

  /// Get the active (non-completed) session, if any.
  Future<FocusSession?> getActiveSession() async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_sessions',
      where: "status NOT IN ('finished', 'cancelled') AND pending_delete = 0",
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  /// Get a session by local ID.
  Future<FocusSession?> getSessionById(String localId) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_sessions',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  /// Get raw row for a session (includes remote_id, pending_actions, dirty).
  Future<Map<String, Object?>?> getRawRow(String localId) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_sessions',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.first);
  }

  /// Insert or update a session from the server response.
  /// Skips overwrite if local row is dirty (conservative conflict resolution).
  /// Returns true if local state changed.
  Future<bool> upsertFromRemote(FocusSession remote) async {
    final db = await _getDb();

    final existing = await db.query(
      'focus_sessions',
      where: 'remote_id = ?',
      whereArgs: [remote.id],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final isDirty = (existing.first['dirty'] as int? ?? 0) == 1;
      if (isDirty) {
        debugPrint(
          '⚠️ [FocusDb] Conflict: session ${remote.id} is dirty locally, skipping remote overwrite',
        );
        return false;
      }

      final existingRow = existing.first;
      final localRoomId = existingRow['room_id'] as String?;
      final roomIdNeedsBackfill =
          remote.roomId != null && (localRoomId == null || localRoomId.isEmpty);
      if (!roomIdNeedsBackfill &&
          (existingRow['status'] as String?) == _statusToString(remote.status) &&
          (existingRow['active_elapsed_sec'] as int? ?? 0) == remote.activeElapsedSec &&
          (existingRow['last_state_change_at'] as String?) ==
              remote.lastStateChangeAt?.toIso8601String() &&
          (existingRow['started_at'] as String?) == remote.startedAt?.toIso8601String() &&
          (existingRow['ended_at'] as String?) == remote.endedAt?.toIso8601String() &&
          (existingRow['task_id'] as String?) == remote.taskId &&
          ((existingRow['earned_coins'] as num?)?.toDouble() ?? 0.0) == remote.earnedCoins &&
          (existingRow['credited_minutes'] as int?) == remote.creditedMinutes &&
          (existingRow['earned_xp'] as int? ?? 0) == remote.earnedXp) {
        return false;
      }
    }

    final now = DateTime.now().toIso8601String();
    final row = <String, Object?>{
      'id': existing.isNotEmpty ? existing.first['id'] as String : remote.id,
      if (remote.roomId != null) 'room_id': remote.roomId,
      'planned_duration_sec': remote.plannedDurationSec,
      'status': _statusToString(remote.status),
      'active_elapsed_sec': remote.activeElapsedSec,
      'last_state_change_at': remote.lastStateChangeAt?.toIso8601String(),
      'started_at': remote.startedAt?.toIso8601String(),
      'ended_at': remote.endedAt?.toIso8601String(),
      'task_id': remote.taskId,
      'earned_coins': remote.earnedCoins,
      'credited_minutes': remote.creditedMinutes,
      'earned_xp': remote.earnedXp,
      'session_day': remote.sessionDay?.toIso8601String().substring(0, 10),
      'created_at': remote.startedAt?.toIso8601String() ?? now,
      'updated_at': now,
      'remote_id': remote.id,
      'version': 0,
      'dirty': 0,
      'pending_delete': 0,
      'pending_actions': '[]',
    };

    if (existing.isNotEmpty) {
      await db.update(
        'focus_sessions',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id'] as String],
      );
    } else {
      await db.insert(
        'focus_sessions',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return true;
  }

  /// Batch upsert multiple sessions from remote in a single transaction.
  /// Wraps all upserts in one DB transaction to reduce fsync() overhead.
  Future<int> upsertFromRemoteBatch(List<FocusSession> sessions) async {
    if (sessions.isEmpty) return 0;
    final db = await _getDb();
    int changed = 0;

    // Pre-fetch existing rows by remote_id in batch
    final remoteIds = sessions.map((s) => s.id).toList();
    final placeholders = List.filled(remoteIds.length, '?').join(',');
    final existingRows = await db.rawQuery(
      'SELECT * FROM focus_sessions WHERE remote_id IN ($placeholders)',
      remoteIds,
    );
    final existingByRemoteId = <String, Map<String, Object?>>{};
    for (final row in existingRows) {
      existingByRemoteId[row['remote_id'] as String] = row;
    }

    await db.transaction((txn) async {
      for (final remote in sessions) {
        final existing = existingByRemoteId[remote.id];

        if (existing != null) {
          final isDirty = (existing['dirty'] as int? ?? 0) == 1;
          if (isDirty) continue;

          final localRoomId = existing['room_id'] as String?;
          final roomIdNeedsBackfill =
              remote.roomId != null && (localRoomId == null || localRoomId.isEmpty);

          if (!roomIdNeedsBackfill &&
              (existing['status'] as String?) == _statusToString(remote.status) &&
              (existing['active_elapsed_sec'] as int? ?? 0) == remote.activeElapsedSec &&
              (existing['last_state_change_at'] as String?) ==
                  remote.lastStateChangeAt?.toIso8601String() &&
              (existing['started_at'] as String?) == remote.startedAt?.toIso8601String() &&
              (existing['ended_at'] as String?) == remote.endedAt?.toIso8601String() &&
              (existing['task_id'] as String?) == remote.taskId &&
              ((existing['earned_coins'] as num?)?.toDouble() ?? 0.0) == remote.earnedCoins &&
              (existing['credited_minutes'] as int?) == remote.creditedMinutes &&
              (existing['earned_xp'] as int? ?? 0) == remote.earnedXp) {
            continue;
          }
        }

        final now = DateTime.now().toIso8601String();
        final row = <String, Object?>{
          'id': existing != null ? existing['id'] as String : remote.id,
          if (remote.roomId != null) 'room_id': remote.roomId,
          'planned_duration_sec': remote.plannedDurationSec,
          'status': _statusToString(remote.status),
          'active_elapsed_sec': remote.activeElapsedSec,
          'last_state_change_at': remote.lastStateChangeAt?.toIso8601String(),
          'started_at': remote.startedAt?.toIso8601String(),
          'ended_at': remote.endedAt?.toIso8601String(),
          'task_id': remote.taskId,
          'earned_coins': remote.earnedCoins,
          'credited_minutes': remote.creditedMinutes,
          'earned_xp': remote.earnedXp,
          'session_day': remote.sessionDay?.toIso8601String().substring(0, 10),
          'created_at': remote.startedAt?.toIso8601String() ?? now,
          'updated_at': now,
          'remote_id': remote.id,
          'version': 0,
          'dirty': 0,
          'pending_delete': 0,
          'pending_actions': '[]',
        };

        if (existing != null) {
          await txn.update(
            'focus_sessions',
            row,
            where: 'id = ?',
            whereArgs: [existing['id'] as String],
          );
        } else {
          await txn.insert(
            'focus_sessions',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        changed++;
      }
    });
    return changed;
  }

  /// Sum of credited_minutes for today's completed sessions (for local rewards calc).
  Future<int> getAlreadyCreditedToday() async {
    final db = await _getDb();
    final today = calc.focusDate(calc.debugNow(), 'UTC', calc.defaultDayCutoffHour);
    final todayStr = today.toIso8601String().substring(0, 10);
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(credited_minutes), 0) as total FROM focus_sessions "
      "WHERE status = 'finished' AND credited_minutes IS NOT NULL "
      "AND session_day = ?",
      [todayStr],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Get credited minutes grouped by session_day for the last 7 days.
  Future<Map<String, int>> getCreditedMinutesByDay({int days = 7}) async {
    final db = await _getDb();
    final now = calc.debugNow();
    final today = calc.focusDate(now, 'UTC', calc.defaultDayCutoffHour);
    final startDate = today.subtract(Duration(days: days - 1));
    final startStr = startDate.toIso8601String().substring(0, 10);

    final result = await db.rawQuery(
      "SELECT session_day, COALESCE(SUM(credited_minutes), 0) as total "
      "FROM focus_sessions "
      "WHERE status = 'finished' "
      "AND credited_minutes IS NOT NULL "
      "AND session_day >= ? "
      "GROUP BY session_day "
      "ORDER BY session_day",
      [startStr],
    );

    final map = <String, int>{};
    // Pre-fill all days with 0
    for (var i = 0; i < days; i++) {
      final d = startDate.add(Duration(days: i));
      map[d.toIso8601String().substring(0, 10)] = 0;
    }
    for (final row in result) {
      final day = row['session_day'] as String;
      map[day] = (row['total'] as int?) ?? 0;
    }
    return map;
  }

  /// Debug: set active_elapsed_sec directly (so backend accepts credited_minutes on sync).
  Future<void> debugSetElapsed(String localId, int elapsedSec) async {
    final db = await _getDb();
    await db.update(
      'focus_sessions',
      {'active_elapsed_sec': elapsedSec, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Apply a state transition locally (optimistic).
  /// Returns the updated FocusSession for immediate UI use.
  Future<FocusSession> updateSessionState(
    String localId,
    String action, {
    int? elapsedOverrideSec,
  }) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_sessions',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('Session $localId not found in local DB');
    }

    final row = Map<String, Object?>.from(rows.first);
    final now = DateTime.now();
    final nowStr = now.toIso8601String();

    // Parse current pending_actions (no deep copy needed — existing items are not modified)
    final actionsJson = row['pending_actions'] as String? ?? '[]';
    final actions = json.decode(actionsJson) as List<dynamic>;

    // Add this action to pending queue (play/pause are local-only, not sent to server)
    if (action != 'play' && action != 'pause') {
      final actionEntry = <String, dynamic>{'action': action};
      if (elapsedOverrideSec != null) {
        actionEntry['elapsed_override_sec'] = elapsedOverrideSec;
      }
      actions.add(actionEntry);
    }

    // Compute elapsed delta if transitioning from running
    final currentStatus = row['status'] as String? ?? 'created';
    int elapsedSec = row['active_elapsed_sec'] as int? ?? 0;
    final lastChangeStr = row['last_state_change_at'] as String?;

    if (currentStatus == 'running' && lastChangeStr != null) {
      final lastChange = DateTime.tryParse(lastChangeStr);
      if (lastChange != null) {
        elapsedSec += now.difference(lastChange).inSeconds;
      }
    }

    // Apply state transition
    final updates = <String, Object?>{
      'active_elapsed_sec': elapsedSec,
      'last_state_change_at': nowStr,
      'updated_at': nowStr,
      'dirty': 1,
      'pending_actions': json.encode(actions),
    };

    switch (action) {
      case 'play':
        updates['status'] = 'running';
        if (row['started_at'] == null) {
          updates['started_at'] = nowStr;
          if (row['session_day'] == null) {
            final sessionDay = calc.focusDate(now, 'UTC', calc.defaultDayCutoffHour);
            updates['session_day'] = sessionDay.toIso8601String().substring(0, 10);
          }
        }
        // Don't accumulate elapsed on play — reset last_state_change_at
        // For resume from paused: keep accumulated active_elapsed_sec
        updates['active_elapsed_sec'] = row['active_elapsed_sec'] as int? ?? 0;
        if (currentStatus == 'running') {
          updates['active_elapsed_sec'] = elapsedSec;
        }
        break;
      case 'pause':
        // running → paused; accumulate elapsed, purely local
        updates['status'] = 'paused';
        updates['active_elapsed_sec'] = elapsedSec;
        break;
      case 'finish':
        // running/paused → finished; rewards come from server after sync
        updates['status'] = 'finished';
        updates['ended_at'] = nowStr;
        updates['credited_minutes'] = elapsedSec ~/ 60;
        // Send elapsed_override_sec so server uses client-tracked time (without pauses)
        final finishElapsed = elapsedOverrideSec ?? elapsedSec;
        updates['active_elapsed_sec'] = finishElapsed;
        updates['credited_minutes'] = finishElapsed ~/ 60;
        // Add elapsed_override_sec to the pending finish action
        if (actions.isNotEmpty) {
          final lastAction = actions.last as Map<String, dynamic>;
          if (lastAction['action'] == 'finish') {
            lastAction['elapsed_override_sec'] = finishElapsed;
          }
        }
        break;
      case 'cancel':
        // created/running/paused → cancelled; no rewards
        updates['status'] = 'cancelled';
        updates['ended_at'] = nowStr;
        updates['credited_minutes'] = 0;
        updates['earned_coins'] = 0.0;
        updates['earned_xp'] = 0;
        // If created (no remote_id), don't add to pending_actions (no server session exists)
        if (currentStatus == 'created' && row['remote_id'] == null) {
          // Remove the cancel action we just added — no server session to cancel
          if (actions.isNotEmpty) {
            final lastAction = actions.last;
            if (lastAction is Map<String, dynamic> && lastAction['action'] == 'cancel') {
              actions.removeLast();
            }
          }
          updates['dirty'] = actions.isNotEmpty ? 1 : 0;
        }
        break;
    }

    await db.update(
      'focus_sessions',
      updates,
      where: 'id = ?',
      whereArgs: [localId],
    );

    // Re-read to return the full updated row
    final updatedRows = await db.query(
      'focus_sessions',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    return _sessionFromRow(updatedRows.first);
  }

  /// Overwrite local session with server response after successful sync.
  /// [sentActionsCount] — number of actions that were sent in this sync batch.
  /// Only those are removed from pending_actions; any actions added concurrently
  /// by the UI are preserved.
  Future<void> applyServerResponse(
    String localId,
    FocusSession server, {
    String? remoteId,
    int sentActionsCount = 0,
  }) async {
    final db = await _getDb();
    final now = DateTime.now().toIso8601String();

    // Re-read current pending_actions to preserve actions added during sync
    final rows = await db.query(
      'focus_sessions',
      columns: ['pending_actions'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    final currentJson = rows.isNotEmpty
        ? rows.first['pending_actions'] as String? ?? '[]'
        : '[]';
    final currentActions = json.decode(currentJson) as List<dynamic>;

    // Remove only the actions we sent; keep any new ones added during sync
    final remaining = sentActionsCount > 0 && sentActionsCount <= currentActions.length
        ? currentActions.sublist(sentActionsCount)
        : <dynamic>[];
    final hasPending = remaining.isNotEmpty;

    await db.update(
      'focus_sessions',
      {
        'status': _statusToString(server.status),
        'active_elapsed_sec': server.activeElapsedSec,
        'last_state_change_at': server.lastStateChangeAt?.toIso8601String(),
        'started_at': server.startedAt?.toIso8601String(),
        'ended_at': server.endedAt?.toIso8601String(),
        'earned_coins': server.earnedCoins,
        'credited_minutes': server.creditedMinutes,
        'earned_xp': server.earnedXp,
        'session_day': server.sessionDay?.toIso8601String().substring(0, 10),
        'updated_at': now,
        'dirty': hasPending ? 1 : 0,
        'pending_actions': json.encode(remaining),
        if (remoteId != null) 'remote_id': remoteId,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Get all dirty (unsynced) session rows.
  Future<List<Map<String, Object?>>> dirtyRows() async {
    final db = await _getDb();
    return db.query('focus_sessions', where: 'dirty = 1');
  }

  /// Check if there are any pending local changes (dirty sessions, purchases, or settings).
  Future<bool> hasDirtyRows() async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT EXISTS('
      '  SELECT 1 FROM focus_sessions WHERE dirty = 1'
      '  UNION ALL'
      '  SELECT 1 FROM focus_pending_purchases'
      '  UNION ALL'
      "  SELECT 1 FROM focus_cache WHERE key = 'pending_profile_settings'"
      ') AS has_dirty',
    );
    return (result.first['has_dirty'] as int) == 1;
  }

  /// Update session task locally and enqueue for sync.
  Future<FocusSession> updateSessionTaskLocally(String localId, String? taskId) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_sessions',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('Session $localId not found in local DB');
    }
    final row = Map<String, Object?>.from(rows.first);
    final actionsJson = row['pending_actions'] as String? ?? '[]';
    final actions = json.decode(actionsJson) as List<dynamic>;
    actions.add(<String, dynamic>{
      'action': 'update_task',
      'task_id': taskId,
    });
    final nowStr = DateTime.now().toIso8601String();
    await db.update(
      'focus_sessions',
      {
        'task_id': taskId,
        'pending_actions': json.encode(actions),
        'updated_at': nowStr,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
    final updated = await db.query(
      'focus_sessions',
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return _sessionFromRow(updated.first);
  }

  /// Set remote_id for a locally created session (after server createSession).
  Future<void> setRemoteId(String localId, String remoteId) async {
    final db = await _getDb();
    await db.update(
      'focus_sessions',
      {
        'remote_id': remoteId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Mark a session as synced.
  Future<void> setSynced(String localId, {required String remoteId}) async {
    final db = await _getDb();
    await db.update(
      'focus_sessions',
      {
        'remote_id': remoteId,
        'dirty': 0,
        'pending_actions': '[]',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Mark a session as clean (dirty=0).
  Future<void> setClean(String localId) async {
    final db = await _getDb();
    // Re-read to check if new actions were added during sync
    final rows = await db.query(
      'focus_sessions',
      columns: ['pending_actions'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final current = json.decode(
        rows.first['pending_actions'] as String? ?? '[]',
      ) as List<dynamic>;
      if (current.isNotEmpty) return; // new actions added during sync, keep dirty
    }
    await db.update(
      'focus_sessions',
      {
        'dirty': 0,
        'pending_actions': '[]',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  // ---------------------------------------------------------------------------
  // Focus task segments
  // ---------------------------------------------------------------------------

  Future<FocusTaskSegment> createSegment(String sessionId, String taskId) async {
    final db = await _getDb();
    final now = DateTime.now();
    final id = generateLocalId();
    final row = <String, Object?>{
      'id': id,
      'session_id': sessionId,
      'task_id': taskId,
      'started_at': now.toIso8601String(),
      'ended_at': null,
      'created_at': now.toIso8601String(),
    };
    await db.insert('focus_task_segments', row);
    return FocusTaskSegment.fromRow(row);
  }

  Future<void> closeActiveSegment(String sessionId, {int? maxSessionElapsedSec}) async {
    final db = await _getDb();
    final now = DateTime.now();

    if (maxSessionElapsedSec == null) {
      await db.rawUpdate(
        'UPDATE focus_task_segments SET ended_at = ? '
        'WHERE session_id = ? AND ended_at IS NULL',
        [now.toIso8601String(), sessionId],
      );
      return;
    }

    // Sum already-closed segments to compute remaining time budget.
    final closedResult = await db.rawQuery(
      "SELECT COALESCE(SUM("
      "CAST((julianday(ended_at) - julianday(started_at)) * 86400 AS INTEGER)"
      "), 0) as closed_sec "
      "FROM focus_task_segments WHERE session_id = ? AND ended_at IS NOT NULL",
      [sessionId],
    );
    final closedSec = (closedResult.first['closed_sec'] as num?)?.toInt() ?? 0;
    final remainingSec = maxSessionElapsedSec - closedSec;

    final openRows = await db.query(
      'focus_task_segments',
      where: 'session_id = ? AND ended_at IS NULL',
      whereArgs: [sessionId],
    );

    for (final row in openRows) {
      final startedAt = DateTime.parse(row['started_at'] as String);
      final DateTime endedAt;
      if (remainingSec > 0) {
        final capEndedAt = startedAt.add(Duration(seconds: remainingSec));
        endedAt = now.isBefore(capEndedAt) ? now : capEndedAt;
      } else {
        endedAt = startedAt;
      }
      await db.rawUpdate(
        'UPDATE focus_task_segments SET ended_at = ? WHERE id = ?',
        [endedAt.toIso8601String(), row['id']],
      );
    }
  }

  Future<List<FocusTaskSegment>> getSegmentsForSession(String sessionId) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_task_segments',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'started_at ASC',
    );
    return rows.map(FocusTaskSegment.fromRow).toList();
  }

  Future<Map<String, int>> getTotalFocusTimeForTasks(List<String> taskIds) async {
    if (taskIds.isEmpty) return {};
    final db = await _getDb();
    final placeholders = List.filled(taskIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT task_id, '
      'SUM(CASE WHEN ended_at IS NOT NULL '
      '  THEN CAST((julianday(ended_at) - julianday(started_at)) * 86400 AS INTEGER) '
      '  ELSE 0 END) as total_sec '
      'FROM focus_task_segments '
      'WHERE task_id IN ($placeholders) '
      'GROUP BY task_id',
      taskIds,
    );
    final result = <String, int>{};
    for (final row in rows) {
      final taskId = row['task_id'] as String;
      final totalSec = (row['total_sec'] as num?)?.toInt() ?? 0;
      if (totalSec > 0) result[taskId] = totalSec;
    }
    return result;
  }

  /// Replace all segments from remote sync (full snapshot).
  /// Deletes all existing segments and inserts the new ones in a single transaction.
  Future<void> replaceAllSegmentsFromRemote(List<FocusTaskSegment> segments) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      await txn.delete('focus_task_segments');
      for (final s in segments) {
        await txn.insert('focus_task_segments', {
          'id': s.id,
          'session_id': s.sessionId,
          'task_id': s.taskId,
          'started_at': s.startedAt.toIso8601String(),
          'ended_at': s.endedAt?.toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  Future<void> deleteSegmentsForSession(String sessionId) async {
    final db = await _getDb();
    await db.delete(
      'focus_task_segments',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // ---------------------------------------------------------------------------
  // Balance, shop items, gamification profile
  // ---------------------------------------------------------------------------

  Future<void> saveBalance(Balance balance) async {
    await _putCache('balance', json.encode({'coins': balance.coins}));
  }

  Future<Balance?> getBalance() async {
    final raw = await _getCache('balance');
    if (raw == null) return null;
    return Balance.fromJson(json.decode(raw) as Map<String, dynamic>);
  }

  Future<void> saveShopItems(List<ShopItem> items) async {
    final list = items.map((i) => {
      'id': i.id,
      'name': i.name,
      'category': i.category.name,
      'price': i.price,
      'owned': i.owned,
      'required_level': i.requiredLevel,
    }).toList();
    await _putCache('shop_items', json.encode(list));
  }

  Future<List<ShopItem>?> getShopItems() async {
    final raw = await _getCache('shop_items');
    if (raw == null) return null;
    final list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => ShopItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveActiveItems(ActiveItems items) async {
    await _putCache('active_items', json.encode(items.toJson()));
  }

  Future<ActiveItems?> getActiveItems() async {
    final raw = await _getCache('active_items');
    if (raw == null) return null;
    return ActiveItems.fromJson(json.decode(raw) as Map<String, dynamic>);
  }

  /// Save list of owned item IDs from sync (lightweight, no full catalog).
  Future<void> saveOwnedItemIds(List<String> ids) async {
    await _putCache('owned_item_ids', json.encode(ids));
  }

  Future<List<String>?> getOwnedItemIds() async {
    final raw = await _getCache('owned_item_ids');
    if (raw == null) return null;
    final list = json.decode(raw) as List<dynamic>;
    return list.map((e) => e.toString()).toList();
  }

  Future<void> saveProfile(GamificationProfile profile) async {
    await _putCache('gamification_profile', json.encode(profile.toJson()));
  }

  Future<GamificationProfile?> getProfile() async {
    final raw = await _getCache('gamification_profile');
    if (raw == null) return null;
    return GamificationProfile.fromJson(json.decode(raw) as Map<String, dynamic>);
  }

  Future<void> saveDailyStats(List<DailyStat> stats) async {
    final list = stats.map((s) => s.toJson()).toList();
    await _putCache('daily_stats', json.encode(list));
  }

  Future<List<DailyStat>?> getDailyStats() async {
    final raw = await _getCache('daily_stats');
    if (raw == null) return null;
    final list = json.decode(raw) as List<dynamic>;
    return list
        .map((e) => DailyStat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Subscription
  // ---------------------------------------------------------------------------

  Future<void> saveSubscription(Map<String, dynamic> data) async {
    await _putCache('subscription', json.encode(data));
  }

  Future<Map<String, dynamic>?> getSubscription() async {
    final raw = await _getCache('subscription');
    if (raw == null) return null;
    return json.decode(raw) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Pending profile settings (local-first, sync in background)
  // ---------------------------------------------------------------------------

  /// Returns the raw JSON string of pending profile settings (for snapshot comparison).
  Future<String?> getRawPendingProfileSettings() async {
    return _getCache('pending_profile_settings');
  }

  /// Returns pending profile settings if any; otherwise null.
  Future<Map<String, dynamic>?> getPendingProfileSettings() async {
    final raw = await _getCache('pending_profile_settings');
    if (raw == null || raw.isEmpty) return null;
    return json.decode(raw) as Map<String, dynamic>?;
  }

  /// Store pending profile settings and update cached profile so UI shows new values immediately.
  Future<void> setPendingProfileSettings({
    Map<int, int>? planMinutes,
    String? homeTz,
    int? dayCutoffHour,
    bool? minimalMode,
    String? themeMode,
    int? focusDurationMin,
    int? shortBreakMin,
    int? longBreakMin,
    int? sessionsBeforeLongBreak,
    bool? autoStartBreak,
    bool? autoStartNextSession,
    bool? adjustDurationAfterSession,
    String? statWidgetConfig,
  }) async {
    final existing = await getPendingProfileSettings() ?? <String, dynamic>{};
    final updates = <String, dynamic>{
      if (planMinutes != null)
        'plan_minutes':
            planMinutes.map((k, v) => MapEntry(k.toString(), v)),
      if (homeTz != null) 'home_tz': homeTz,
      if (dayCutoffHour != null) 'day_cutoff_hour': dayCutoffHour,
      if (minimalMode != null) 'minimal_mode': minimalMode,
      if (themeMode != null) 'theme_mode': themeMode,
      if (focusDurationMin != null) 'focus_duration_min': focusDurationMin,
      if (shortBreakMin != null) 'short_break_min': shortBreakMin,
      if (longBreakMin != null) 'long_break_min': longBreakMin,
      if (sessionsBeforeLongBreak != null) 'sessions_before_long_break': sessionsBeforeLongBreak,
      if (autoStartBreak != null) 'auto_start_break': autoStartBreak,
      if (autoStartNextSession != null) 'auto_start_next_session': autoStartNextSession,
      if (adjustDurationAfterSession != null) 'adjust_duration_after_session': adjustDurationAfterSession,
      if (statWidgetConfig != null) 'stat_widget_config': statWidgetConfig,
    };
    existing.addAll(updates);
    await _putCache(
      'pending_profile_settings',
      json.encode(existing),
    );
    final current = await getProfile();
    if (current != null) {
      await saveProfile(current.copyWith(
        planMinutes: planMinutes,
        homeTz: homeTz,
        dayCutoffHour: dayCutoffHour,
        minimalMode: minimalMode,
        themeMode: themeMode,
        focusDurationMin: focusDurationMin,
        shortBreakMin: shortBreakMin,
        longBreakMin: longBreakMin,
        sessionsBeforeLongBreak: sessionsBeforeLongBreak,
        autoStartBreak: autoStartBreak,
        autoStartNextSession: autoStartNextSession,
        adjustDurationAfterSession: adjustDurationAfterSession,
        statWidgetConfig: statWidgetConfig,
      ));
    }
  }

  /// Clear pending profile settings after successful server sync.
  Future<void> clearPendingProfileSettings() async {
    final db = await _getDb();
    await db.delete(
      'focus_cache',
      where: 'key = ?',
      whereArgs: ['pending_profile_settings'],
    );
  }

  // ---------------------------------------------------------------------------
  // Pending purchases (local-first, sync in background)
  // ---------------------------------------------------------------------------

  /// Add a pending shop item purchase. Sync service will push to server.
  Future<void> insertPendingShopPurchase(String itemId) async {
    final db = await _getDb();
    await db.insert('focus_pending_purchases', {
      'type': 'shop_item',
      'item_id': itemId,
      'quantity': null,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// List all pending purchases for background sync.
  Future<List<Map<String, dynamic>>> getPendingPurchases() async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_pending_purchases',
      orderBy: 'id ASC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Remove a pending purchase after successful server sync.
  Future<void> deletePendingPurchase(int id) async {
    final db = await _getDb();
    await db.delete(
      'focus_pending_purchases',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveCacheValue(String key, String value) async {
    await _putCache(key, value);
  }

  Future<String?> getCacheValue(String key) async {
    return _getCache(key);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _putCache(String key, String value) async {
    final db = await _getDb();
    await db.insert(
      'focus_cache',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _getCache(String key) async {
    final db = await _getDb();
    final rows = await db.query(
      'focus_cache',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  FocusSession _sessionFromRow(Map<String, Object?> row) {
    return FocusSession(
      id: row['id'] as String,
      plannedDurationSec: row['planned_duration_sec'] as int? ?? 0,
      status: _parseStatus(row['status'] as String?),
      activeElapsedSec: row['active_elapsed_sec'] as int? ?? 0,
      lastStateChangeAt: _parseDate(row['last_state_change_at']),
      startedAt: _parseDate(row['started_at']),
      endedAt: _parseDate(row['ended_at']),
      taskId: row['task_id'] as String?,
      earnedCoins: (row['earned_coins'] as num?)?.toDouble() ?? 0.0,
      creditedMinutes: row['credited_minutes'] as int?,
      earnedXp: row['earned_xp'] as int? ?? 0,
      sessionDay: _parseDate(row['session_day']),
    );
  }

  static FocusSessionStatus _parseStatus(String? value) {
    switch (value) {
      case 'running':
        return FocusSessionStatus.running;
      case 'paused':
        return FocusSessionStatus.paused;
      case 'finished':
        return FocusSessionStatus.finished;
      case 'stopped':
      case 'cancelled':
        return FocusSessionStatus.cancelled;
      // Legacy mapping for cached data
      case 'stopped_pending_credit':
      case 'credited_undoable':
      case 'credited_final':
        return FocusSessionStatus.finished;
      case 'awaiting_confirm':
      case 'completed':
        return FocusSessionStatus.cancelled;
      case 'created':
      default:
        return FocusSessionStatus.created;
    }
  }

  static String _statusToString(FocusSessionStatus status) {
    switch (status) {
      case FocusSessionStatus.created:
        return 'created';
      case FocusSessionStatus.running:
        return 'running';
      case FocusSessionStatus.paused:
        return 'paused';
      case FocusSessionStatus.finished:
        return 'finished';
      case FocusSessionStatus.cancelled:
        return 'cancelled';
    }
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
