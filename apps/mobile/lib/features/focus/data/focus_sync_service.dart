import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../auth/data/token_manager.dart';
import '../models/focus_models.dart';
import 'focus_api.dart';
import 'focus_db.dart';
import 'gamification_api.dart';

String _generateUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class FocusSyncService {
  FocusSyncService._();
  static final FocusSyncService instance = FocusSyncService._();

  bool _syncInProgress = false;
  Timer? _debounce;
  void Function()? onSyncComplete;

  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
  }

  /// Schedule a sync after a local mutation (e.g. session create, purchase).
  void scheduleSync({Duration delay = const Duration(seconds: 2)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, _maybeSync);
  }

  /// Push-only sync: push all dirty data without pulling.
  /// Pull is now handled by unified /sync endpoint via AggregatedSyncService.
  Future<bool> pushDirtyOnly() async {
    if (_syncInProgress) {
      debugPrint('🔍 [DIAG] pushDirtyOnly SKIPPED: _syncInProgress=true');
      return false;
    }
    if (!(await TokenManager.isAuthenticated)) return false;
    _debounce?.cancel();
    _syncInProgress = true;
    try {
      final sessions = await _pushDirtySessions();
      final purchases = await _pushPendingPurchases();
      final profile = await _pushPendingProfileSettings();
      return sessions || purchases || profile;
    } finally {
      _syncInProgress = false;
    }
  }


  /// Full sync: push dirty + pull sessions + refresh snapshot.
  /// NOTE: Pull is now handled by unified /sync. This method is kept for
  /// standalone use (e.g. app start snapshot with evaluate_pending_days).
  Future<bool> syncNowFull() async {
    if (_syncInProgress) return false;
    if (!(await TokenManager.isAuthenticated)) return false;
    _debounce?.cancel();
    _syncInProgress = true;
    try {
      final dirtySessionChanges = await _pushDirtySessions();
      final purchaseChanges = await _pushPendingPurchases();
      final profileChanges = await _pushPendingProfileSettings();
      await _refreshData();
      onSyncComplete?.call();
      return dirtySessionChanges || purchaseChanges || profileChanges;
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _maybeSync() async {
    if (_syncInProgress) return;
    if (!(await TokenManager.isAuthenticated)) return;
    _syncInProgress = true;
    try {
      await _pushDirtySessions();
      await _pushPendingPurchases();
      await _pushPendingProfileSettings();
    } catch (e, stackTrace) {
      developer.log(
        '❌ [FocusSyncService] Sync failed: ${e.runtimeType} $e',
        name: 'FocusSyncService',
        error: e,
        stackTrace: stackTrace,
      );
      if (TokenManager.isAuthError(e)) {
        await TokenManager.handleAuthFailure(e);
      }
    } finally {
      _syncInProgress = false;
    }
  }

  /// Push a specific session to server and return the server-updated session.
  /// Does NOT check _syncInProgress — used for finish flow where we need
  /// the server response (rewards) immediately for the completion dialog.
  /// Returns null if offline, unauthenticated, or on error.
  Future<FocusSession?> pushSessionForResult(String localId) async {
    debugPrint('🔍 [DIAG] pushSessionForResult START localId=$localId');

    final isAuth = await TokenManager.isAuthenticated;
    if (!isAuth) {
      debugPrint('🔍 [DIAG] pushSessionForResult EXIT: not authenticated');
      return null;
    }

    final db = FocusDb();
    final api = FocusApi();

    try {
      final row = await db.getRawRow(localId);
      if (row == null) {
        debugPrint('🔍 [DIAG] pushSessionForResult EXIT: row is null for localId=$localId');
        return null;
      }

      var remoteId = row['remote_id'] as String?;
      debugPrint('🔍 [DIAG] remoteId=$remoteId, dirty=${row['dirty']}, pending_actions=${row['pending_actions']}');

      if (remoteId == null || remoteId.isEmpty) {
        final rawDuration = row['planned_duration_sec'] as int? ?? 0;
        // Stopwatch mode uses 0 locally; server requires 300..10800, so send max
        final plannedDurationSec = rawDuration > 0 ? rawDuration : 10800;
        final taskId = row['task_id'] as String?;
        final roomId = row['room_id'] as String? ?? '';
        debugPrint('🔍 [DIAG] Creating session on server (plannedDurationSec=$plannedDurationSec, taskId=$taskId, roomId=$roomId)...');
        final created = await api.createSession(
          plannedDurationSec: plannedDurationSec,
          roomId: roomId,
          taskId: taskId,
        );
        remoteId = created.id;
        debugPrint('🔍 [DIAG] Session created, remoteId=$remoteId');
        await db.setRemoteId(localId, remoteId);
      }

      final actionsJson = row['pending_actions'] as String? ?? '[]';
      final actions = json.decode(actionsJson) as List<dynamic>;

      if (actions.isEmpty) {
        debugPrint('🔍 [DIAG] actions empty — returning local session (background sync already pushed)');
        await db.setClean(localId);
        // Actions already pushed by background sync — return updated local session
        // which should have server rewards applied via applyServerResponse.
        return db.getSessionById(localId);
      }

      // Split task updates vs state actions
      final taskUpdates = <Map<String, dynamic>>[];
      final stateActions = <Map<String, dynamic>>[];
      for (final entry in actions) {
        final map = entry as Map<String, dynamic>;
        if (map['action'] == 'update_task') {
          taskUpdates.add(map);
        } else if (map['action'] != 'play' && map['action'] != 'pause') {
          stateActions.add(map);
        }
      }

      debugPrint('🔍 [DIAG] actions=${actions.length}, stateActions=${stateActions.length}, taskUpdates=${taskUpdates.length}');

      for (final tu in taskUpdates) {
        await api.updateSessionTask(
          sessionId: remoteId,
          taskId: tu['task_id'] as String?,
        );
      }

      // Load segments for this session to send with batchActions
      final segments = await db.getSegmentsForSession(localId);
      final segmentsPayload = segments.map((s) => s.toJson()).toList();
      debugPrint('🔍 [DIAG] segments=${segmentsPayload.length}');

      FocusSession? serverSession;
      if (stateActions.isNotEmpty) {
        final batchPayload = stateActions.map((a) {
          final m = <String, dynamic>{'action': a['action']};
          if (a['elapsed_override_sec'] != null) {
            m['elapsed_override_sec'] = a['elapsed_override_sec'];
          }
          return m;
        }).toList();
        debugPrint('🔍 [DIAG] Sending batchActions to remoteId=$remoteId with ${batchPayload.length} actions: $batchPayload');
        final result = await api.batchActions(
          sessionId: remoteId,
          actions: batchPayload,
          idempotencyKey: _generateUuidV4(),
          segments: segmentsPayload.isNotEmpty ? segmentsPayload : null,
        );
        serverSession = result.session;
        debugPrint('🔍 [DIAG] batchActions response: hasSession=true, coins=${result.session.earnedCoins}');
      } else {
        debugPrint('🔍 [DIAG] stateActions empty after filtering — no batchActions call, serverSession will be null');
      }

      if (serverSession != null) {
        await db.applyServerResponse(
          localId,
          serverSession,
          remoteId: remoteId,
          sentActionsCount: actions.length,
        );
      } else {
        await db.setClean(localId);
      }

      debugPrint('🔍 [DIAG] pushSessionForResult END returning serverSession=${serverSession != null}');
      return serverSession;
    } catch (e, stackTrace) {
      debugPrint('🔍 [DIAG] pushSessionForResult EXCEPTION type=${e.runtimeType}, message=$e');
      developer.log(
        'pushSessionForResult failed for $localId: $e',
        name: 'FocusSyncService',
        error: e,
        stackTrace: stackTrace,
      );
      if (TokenManager.isAuthError(e)) {
        await TokenManager.handleAuthFailure(e);
      }
      return null;
    }
  }

  Future<bool> _pushDirtySessions() async {
    final db = FocusDb();
    final api = FocusApi();
    final rows = await db.dirtyRows();
    final hasDirtyRows = rows.isNotEmpty;

    for (final row in rows) {
      try {
        final localId = row['id'] as String;
        var remoteId = row['remote_id'] as String?;

        if (remoteId == null || remoteId.isEmpty) {
          // Server creates session directly in 'running' state
          final rawDuration = row['planned_duration_sec'] as int? ?? 0;
          // Stopwatch mode uses 0 locally; server requires 300..10800, so send max
          final plannedDurationSec = rawDuration > 0 ? rawDuration : 10800;
          final taskId = row['task_id'] as String?;
          final roomId = row['room_id'] as String? ?? '';
          final session = await api.createSession(
            plannedDurationSec: plannedDurationSec,
            roomId: roomId,
            taskId: taskId,
          );
          remoteId = session.id;
          await db.setRemoteId(localId, remoteId);
        }

        final actionsJson = row['pending_actions'] as String? ?? '[]';
        final actions = json.decode(actionsJson) as List<dynamic>;

        if (actions.isEmpty) {
          await db.setClean(localId);
          continue;
        }

        // Split into task updates (must use PATCH) and state actions (can batch)
        final taskUpdates = <Map<String, dynamic>>[];
        final stateActions = <Map<String, dynamic>>[];
        for (final entry in actions) {
          final map = entry as Map<String, dynamic>;
          if (map['action'] == 'update_task') {
            taskUpdates.add(map);
          } else if (map['action'] != 'play' && map['action'] != 'pause') {
            // 'play' and 'pause' are local-only; server doesn't know about them
            stateActions.add(map);
          }
        }

        // Push task updates one by one (different endpoint)
        for (final tu in taskUpdates) {
          await api.updateSessionTask(
            sessionId: remoteId,
            taskId: tu['task_id'] as String?,
          );
        }

        // Load segments for this session to include in batchActions
        final segments = await db.getSegmentsForSession(localId);
        final segmentsPayload = segments.map((s) => s.toJson()).toList();

        // Batch push all state actions in a single request
        dynamic lastSession;
        if (stateActions.isNotEmpty) {
          final batchPayload = stateActions.map((a) {
            final m = <String, dynamic>{'action': a['action']};
            if (a['elapsed_override_sec'] != null) {
              m['elapsed_override_sec'] = a['elapsed_override_sec'];
            }
            return m;
          }).toList();
          final result = await api.batchActions(
            sessionId: remoteId,
            actions: batchPayload,
            idempotencyKey: _generateUuidV4(),
            segments: segmentsPayload.isNotEmpty ? segmentsPayload : null,
          );
          lastSession = result.session;
        }

        if (lastSession != null) {
          await db.applyServerResponse(
            localId,
            lastSession,
            remoteId: remoteId,
            sentActionsCount: actions.length,
          );
        } else {
          await db.setClean(localId);
        }
      } catch (e, stackTrace) {
        final localId = row['id'] as String;
        final remoteId = row['remote_id'] as String?;
        developer.log(
          '❌ [FocusSyncService] Push failed for session $localId (remote=$remoteId): $e',
          name: 'FocusSyncService',
          error: e,
          stackTrace: stackTrace,
        );
        // Keep dirty, will retry on next cycle
      }
    }
    return hasDirtyRows;
  }

  Future<bool> _pushPendingProfileSettings() async {
    final db = FocusDb();
    // Snapshot the raw pending string BEFORE the push so we can detect
    // concurrent writes that happened during the network call.
    final rawBefore = await db.getRawPendingProfileSettings();
    if (rawBefore == null || rawBefore.isEmpty) return false;
    final pending = json.decode(rawBefore) as Map<String, dynamic>;
    try {
      Map<int, int>? planMinutes;
      final rawPlanMinutes = pending['plan_minutes'];
      if (rawPlanMinutes is Map) {
        planMinutes = rawPlanMinutes.map(
          (k, v) => MapEntry(int.parse(k.toString()), v as int),
        );
      }
      await GamificationApi().updateProfile(
        planMinutes: planMinutes,
        homeTz: pending['home_tz'] as String?,
        dayCutoffHour: pending['day_cutoff_hour'] as int?,
        minimalMode: pending['minimal_mode'] as bool?,
        themeMode: pending['theme_mode'] as String?,
        focusDurationMin: pending['focus_duration_min'] as int?,
        shortBreakMin: pending['short_break_min'] as int?,
        longBreakMin: pending['long_break_min'] as int?,
        sessionsBeforeLongBreak: pending['sessions_before_long_break'] as int?,
        autoStartBreak: pending['auto_start_break'] as bool?,
        autoStartNextSession: pending['auto_start_next_session'] as bool?,
        adjustDurationAfterSession: pending['adjust_duration_after_session'] as bool?,
        statWidgetConfig: pending['stat_widget_config'] as String?,
      );
      // Only clear pending if no new writes happened during the push.
      // If pending changed, a subsequent push will pick up the new values.
      final rawAfter = await db.getRawPendingProfileSettings();
      if (rawBefore == rawAfter) {
        await db.clearPendingProfileSettings();
      }
    } catch (e, stackTrace) {
      developer.log(
        '❌ [FocusSyncService] Push profile settings failed: $e',
        name: 'FocusSyncService',
        error: e,
        stackTrace: stackTrace,
      );
    }
    return true;
  }

  Future<bool> _pushPendingPurchases() async {
    final db = FocusDb();
    final focusApi = FocusApi();
    final pending = await db.getPendingPurchases();
    final hasPendingPurchases = pending.isNotEmpty;

    for (final row in pending) {
      final id = row['id'] as int;
      final type = row['type'] as String?;
      try {
        if (type == 'shop_item') {
          final itemId = row['item_id'] as String?;
          if (itemId == null || itemId.isEmpty) continue;
          await focusApi.purchaseItem(itemId);
        } else {
          continue;
        }
        await db.deletePendingPurchase(id);
      } catch (e, stackTrace) {
        developer.log(
          '❌ [FocusSyncService] Push purchase failed (id=$id, type=$type): $e',
          name: 'FocusSyncService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    return hasPendingPurchases;
  }

  Future<void> _refreshData() async {
    final db = FocusDb();
    final api = FocusApi();

    try {
      final snapshot = await api.getSnapshot();
      await Future.wait([
        db.saveBalance(snapshot.balance),
        db.saveShopItems(snapshot.shopItems),
        db.saveProfile(snapshot.profile),
        db.saveActiveItems(snapshot.activeItems),
      ]);
    } catch (e) {
      developer.log(
        '⚠️ [FocusSyncService] Snapshot refresh failed: $e (using stale data)',
        name: 'FocusSyncService',
      );
    }
  }
}
