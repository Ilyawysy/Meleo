import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/database/database_provider.dart';
import '../../auth/data/token_manager.dart';
import '../models/focus_room.dart';
import '../models/task.dart';
import '../models/checklist_item.dart';
import 'focus_room_db.dart';
import 'focus_room_api.dart';
import 'task_db.dart';
import 'task_api.dart';
import 'checklist_item_db.dart';
import 'checklist_api.dart';

/// Unified sync service for focus rooms, tasks, checklist items.
/// Focus sessions/segments push is handled by [FocusSyncService].
class FocusRoomSyncService {
  FocusRoomSyncService._();
  static final FocusRoomSyncService instance = FocusRoomSyncService._();

  bool _syncInProgress = false;
  Timer? _debounce;
  void Function()? onSyncComplete;

  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
  }

  void scheduleSync({Duration delay = const Duration(seconds: 2)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, _maybeSync);
  }

  Future<void> _maybeSync() async {
    if (_syncInProgress) {
      // ignore: avoid_print
      print('[DIAG] FocusRoomSync._maybeSync: skip (in progress)');
      return;
    }
    final isAuth = await TokenManager.isAuthenticated;
    if (!isAuth) {
      // ignore: avoid_print
      print('[DIAG] FocusRoomSync._maybeSync: skip (not authenticated)');
      return;
    }
    // ignore: avoid_print
    print('[DIAG] FocusRoomSync._maybeSync: starting push');
    _syncInProgress = true;
    bool success = false;
    try {
      await _pushDirtyRooms();
      await _pushDirtyTasks();
      await _pushDirtyChecklistItems();
      success = true;
    } catch (e, stackTrace) {
      developer.log(
        '❌ [FocusRoomSyncService] Sync failed: ${e.runtimeType} $e',
        name: 'FocusRoomSyncService',
        error: e,
        stackTrace: stackTrace,
      );
      if (TokenManager.isAuthError(e)) {
        await TokenManager.handleAuthFailure(e);
      }
    } finally {
      _syncInProgress = false;
      if (success) onSyncComplete?.call();
    }
  }

  // ---------------------------------------------------------------------------
  // Pull (apply remote changes received from /sync endpoint)
  // ---------------------------------------------------------------------------

  Future<int> applyRemoteRooms(List<Map<String, dynamic>> items) async {
    final db = FocusRoomDb();
    int count = 0;
    for (final map in items) {
      final isDeleted = map['deleted'] as bool? ?? false;
      if (isDeleted) {
        // Soft-remove not implemented yet (Phase 4). Skip.
        count++;
        continue;
      }
      final room = FocusRoom.fromJson(map);
      final changed = await db.applyRemote(room);
      if (changed) count++;
    }
    return count;
  }

  Future<int> applyRemoteTasks(List<Map<String, dynamic>> items) async {
    final db = FocusTaskDb();
    int count = 0;
    for (final map in items) {
      final isDeleted = map['deleted'] as bool? ?? false;
      if (isDeleted) {
        final remoteId = map['id']?.toString();
        if (remoteId != null && remoteId.isNotEmpty) {
          await db.deleteByRemoteIdHard(remoteId);
          count++;
        }
        continue;
      }
      final task = Task.fromJson(map);
      final changed = await db.applyRemote(task);
      if (changed) count++;
    }
    return count;
  }

  Future<int> applyRemoteChecklistItems(List<Map<String, dynamic>> items) async {
    final db = FocusChecklistItemDb();
    int count = 0;
    for (final map in items) {
      final id = map['id']?.toString() ?? '';
      final taskId = map['task_id']?.toString() ?? '';
      if (id.isEmpty || taskId.isEmpty) continue;
      DateTime createdAt;
      DateTime updatedAt;
      try {
        createdAt = DateTime.parse(map['created_at'] as String).toUtc();
      } catch (_) {
        createdAt = DateTime.now().toUtc();
      }
      try {
        updatedAt = DateTime.parse(map['updated_at'] as String).toUtc();
      } catch (_) {
        updatedAt = DateTime.now().toUtc();
      }
      final item = ChecklistItem(
        id: id,
        taskId: taskId,
        title: map['title'] as String? ?? '',
        isDone: map['is_done'] as bool? ?? false,
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      await db.upsertFromRemote(item);
      count++;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // Push (dirty rows → server)
  // ---------------------------------------------------------------------------

  Future<void> _pushDirtyRooms() async {
    final db = FocusRoomDb();
    final api = FocusRoomApi();
    final rows = await db.listDirty();
    // ignore: avoid_print
    print('[DIAG] _pushDirtyRooms: ${rows.length} dirty rows to push');

    for (final row in rows) {
      try {
        final localId = row['id'] as String;
        final remoteId = row['remote_id'] as String?;
        final isPendingDelete = (row['pending_delete'] as int? ?? 0) == 1;
        final isArchived = (row['archived'] as int? ?? 0) == 1;

        if (isPendingDelete) {
          if (remoteId != null && remoteId.isNotEmpty) {
            await api.archiveRoom(remoteId);
          }
          await db.markClean(localId);
          continue;
        }

        final room = FocusRoom.fromDb(row);

        if (remoteId == null || remoteId.isEmpty) {
          // ignore: avoid_print
          print('[DIAG] _pushDirtyRooms: POST createRoom title="${room.title}"');
          final created = await api.createRoom(room);
          // ignore: avoid_print
          print('[DIAG] _pushDirtyRooms: POST ok, remote_id=${created.id}');
          await db.setSynced(localId, remoteId: created.id);
        } else {
          final patch = <String, dynamic>{
            'title': room.title,
            'color': room.color,
            'type': room.type.name,
            'sort_order': room.sortOrder,
            'archived': isArchived,
          };
          if (room.sprintGoal != null) patch['sprint_goal'] = room.sprintGoal;
          if (room.sprintDeadline != null) {
            patch['sprint_deadline'] = room.sprintDeadline!.toIso8601String();
          }
          if (room.sprintTotalHours != null) {
            patch['sprint_total_hours'] = room.sprintTotalHours;
          }
          if (room.focusDurationMin != null) {
            patch['focus_duration_min'] = room.focusDurationMin;
          }
          if (room.breakMin != null) {
            patch['break_min'] = room.breakMin;
          }
          await api.updateRoom(remoteId, patch);
          await db.markClean(localId);
        }
      } catch (e, stackTrace) {
        // ignore: avoid_print
        print('[DIAG] _pushDirtyRooms: FAILED for ${row['id']}: $e');
        developer.log(
          '❌ [FocusRoomSyncService] Room push failed for ${row['id']}: $e',
          name: 'FocusRoomSyncService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _pushDirtyTasks() async {
    final db = FocusTaskDb();
    final api = FocusTaskApi();
    final rows = await db.listDirty();

    final List<Map<String, Object?>> deletes = [];
    final List<Map<String, Object?>> creates = [];
    final List<Map<String, Object?>> updates = [];

    for (final row in rows) {
      final isPendingDelete = (row['pending_delete'] as int? ?? 0) == 1;
      final remoteId = row['remote_id'] as String?;
      if (isPendingDelete) {
        deletes.add(row);
      } else if (remoteId == null || remoteId.isEmpty) {
        creates.add(row);
      } else {
        updates.add(row);
      }
    }

    for (final row in deletes) {
      try {
        final localId = row['id'] as String;
        final remoteId = row['remote_id'] as String?;
        if (remoteId != null && remoteId.isNotEmpty) {
          await api.deleteTask(remoteId);
        }
        await db.deleteHard(localId);
      } catch (e, stackTrace) {
        developer.log(
          '❌ [FocusRoomSyncService] Task delete failed: $e',
          name: 'FocusRoomSyncService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    for (final row in creates) {
      try {
        final localId = row['id'] as String;
        final roomId = row['room_id'] as String? ?? '';
        if (roomId.isEmpty) continue;

        final roomRemoteId = await _getRoomRemoteId(roomId);
        if (roomRemoteId == null || roomRemoteId.isEmpty) continue;

        final task = Task.fromDb(row);
        final created = await api.createInRoom(roomRemoteId, task);
        await db.setSynced(localId, remoteId: created.id);
      } catch (e, stackTrace) {
        developer.log(
          '❌ [FocusRoomSyncService] Task create failed: $e',
          name: 'FocusRoomSyncService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    for (final row in updates) {
      try {
        final localId = row['id'] as String;
        final remoteId = row['remote_id'] as String?;
        if (remoteId == null || remoteId.isEmpty) continue;

        final patch = <String, dynamic>{
          'status': row['status'] ?? 'not_done',
        };
        if (row['title'] != null) patch['title'] = row['title'];
        if (row['description'] != null) patch['description'] = row['description'];
        if (row['sort_order'] != null) patch['sort_order'] = row['sort_order'];
        if (row['completed_at'] != null) patch['completed_at'] = row['completed_at'];

        await api.updateTask(remoteId, patch);
        await db.markClean(localId);
      } catch (e, stackTrace) {
        developer.log(
          '❌ [FocusRoomSyncService] Task update failed: $e',
          name: 'FocusRoomSyncService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _pushDirtyChecklistItems() async {
    final db = FocusChecklistItemDb();
    final api = FocusChecklistApi();
    final taskDb = FocusTaskDb();
    final rows = await db.dirtyRows();

    for (final row in rows) {
      try {
        final localId = row['id'] as String;
        final remoteId = row['remote_id'] as String?;
        final taskLocalId = row['task_id'] as String;
        final isPendingDelete = (row['pending_delete'] as int? ?? 0) == 1;

        final remoteTaskId = await taskDb.getRemoteId(taskLocalId);
        if (remoteTaskId == null || remoteTaskId.isEmpty) continue;

        if (isPendingDelete) {
          if (remoteId != null && remoteId.isNotEmpty) {
            await api.delete(remoteTaskId, remoteId);
          }
          await db.deleteHard(localId);
        } else if (remoteId == null || remoteId.isEmpty) {
          final created = await api.create(
            remoteTaskId,
            title: row['title'] as String? ?? '',
            sortOrder: row['sort_order'] as int? ?? 0,
          );
          await db.setSynced(localId, remoteId: created.id);
        } else {
          await api.update(
            remoteTaskId,
            remoteId,
            title: row['title'] as String?,
            isDone: (row['is_done'] as int? ?? 0) == 1,
            sortOrder: row['sort_order'] as int?,
          );
          await db.setClean(localId);
        }
      } catch (e, stackTrace) {
        developer.log(
          '❌ [FocusRoomSyncService] Checklist push failed: $e',
          name: 'FocusRoomSyncService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Resolve a local room_id to its remote_id (for task create push).
  Future<String?> _getRoomRemoteId(String localRoomId) async {
    final dbProvider = DatabaseProvider();
    final db = await dbProvider.getDatabase();
    final rows = await db.query(
      'focus_rooms',
      columns: ['remote_id'],
      where: 'id = ?',
      whereArgs: [localRoomId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['remote_id'] as String?;
  }
}
