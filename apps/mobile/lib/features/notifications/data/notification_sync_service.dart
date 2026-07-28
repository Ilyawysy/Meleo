import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';
import '../../auth/data/token_manager.dart';
import 'notification_db.dart';
import 'notification_api.dart';

class NotificationSyncService {
  NotificationSyncService._();
  static final NotificationSyncService instance = NotificationSyncService._();

  bool _syncInProgress = false;
  Timer? _debounce;
  VoidCallback? onSyncComplete;

  void _logSyncError({
    required String stage,
    required String localId,
    String? remoteId,
    required Object error,
    StackTrace? stackTrace,
  }) {
    final remoteIdStr = remoteId != null && remoteId.isNotEmpty
        ? 'remote_id=$remoteId'
        : 'no remote_id';
    final errorType = error.runtimeType.toString();
    final errorMsg = error.toString();

    developer.log(
      '❌ [NotificationSyncService] Sync error in $stage | local_id=$localId, $remoteIdStr | '
      'error_type=$errorType, error=$errorMsg | '
      'result=keep_dirty_will_retry',
      name: 'NotificationSyncService',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
  }

  void scheduleSync({Duration delay = const Duration(seconds: 2)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, _maybeSync);
  }

  Future<void> _maybeSync() async {
    if (_syncInProgress) return;
    if (!(await TokenManager.isAuthenticated)) return;
    _syncInProgress = true;
    bool success = false;
    try {
      await _syncDirtyNotifications();
      success = true;
    } catch (e, stackTrace) {
      developer.log(
        '❌ [NotificationSyncService] Sync failed: ${e.runtimeType} $e',
        name: 'NotificationSyncService',
        error: e,
        stackTrace: stackTrace,
      );
      if (TokenManager.isAuthError(e)) {
        await TokenManager.handleAuthFailure(e);
        developer.log(
          '⚠️ [NotificationSyncService] Auth error handled (token cleared)',
          name: 'NotificationSyncService',
        );
      }
    } finally {
      _syncInProgress = false;
      if (success) onSyncComplete?.call();
    }
  }

  Future<bool> syncNowFull() async {
    if (!(await TokenManager.isAuthenticated)) return false;
    final pulledChanges = await _pullAllNotifications();
    final pushedChanges = await _syncDirtyNotifications();
    return pulledChanges || pushedChanges;
  }

  Future<bool> _syncDirtyNotifications() async {
    final db = NotificationDb();
    final api = NotificationApi();
    final rows = await db.dirtyRows();
    final hasDirtyRows = rows.isNotEmpty;

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

    if (deletes.isNotEmpty) {
      await _processBatches<Map<String, Object?>>(deletes, (row) async {
        try {
          final localId = row['id'] as String;
          final remoteId = row['remote_id'] as String?;
          if (remoteId != null && remoteId.isNotEmpty) {
            await api.delete(remoteId);
          }
          await db.deleteHard(localId);
        } catch (e, stackTrace) {
          final localId = row['id'] as String;
          final remoteId = row['remote_id'] as String?;
          _logSyncError(
            stage: 'push/delete',
            localId: localId,
            remoteId: remoteId,
            error: e,
            stackTrace: stackTrace,
          );
        }
      }, batchSize: 3);
    }

    if (creates.isNotEmpty) {
      await _processBatches<Map<String, Object?>>(creates, (row) async {
        try {
          final localId = row['id'] as String;
          final title = (row['title'] as String?) ?? '';
          final timeStr = row['time'] as String?;
          final DateTime time = timeStr != null
              ? DateTime.parse(timeStr)
              : DateTime.now();
          final recurrence = (row['recurrence'] as String?) ?? 'none';

          final created = await api.create(
            title: title,
            time: time,
            recurrence: recurrence,
          );
          await db.setSynced(localId, remoteId: created.id);
        } catch (e, stackTrace) {
          final localId = row['id'] as String;
          _logSyncError(
            stage: 'push/create',
            localId: localId,
            remoteId: null,
            error: e,
            stackTrace: stackTrace,
          );
        }
      }, batchSize: 3);
    }

    if (updates.isNotEmpty) {
      await _processBatches<Map<String, Object?>>(updates, (row) async {
        try {
          final localId = row['id'] as String;
          final remoteId = row['remote_id'] as String?;
          if (remoteId == null || remoteId.isEmpty) return;
          final title = row['title'] as String?;
          final timeStr = row['time'] as String?;
          final DateTime? time = timeStr != null
              ? DateTime.parse(timeStr)
              : null;
          final recurrence = row['recurrence'] as String?;

          await api.update(
            remoteId,
            title: title,
            time: time,
            recurrence: recurrence,
          );
          await db.setClean(localId);
        } catch (e, stackTrace) {
          final localId = row['id'] as String;
          final remoteId = row['remote_id'] as String?;
          _logSyncError(
            stage: 'push/update',
            localId: localId,
            remoteId: remoteId,
            error: e,
            stackTrace: stackTrace,
          );
        }
      }, batchSize: 3);
    }
    return hasDirtyRows;
  }

  Future<void> _processBatches<T>(
    List<T> items,
    Future<void> Function(T item) op, {
    int batchSize = 3,
  }) async {
    if (items.isEmpty) return;
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      final futures = items.sublist(i, end).map(op).toList();
      await Future.wait(futures);
    }
  }

  Future<bool> _pullAllNotifications() async {
    final api = NotificationApi();
    final db = NotificationDb();
    const pageSize = 50;
    var offset = 0;
    var hasPulledChanges = false;
    while (true) {
      final items = await api.list(limit: pageSize, offset: offset);
      if (items.isEmpty) break;
      for (final n in items) {
        final changed = await db.upsertFromRemote(n);
        hasPulledChanges = hasPulledChanges || changed;
      }
      offset += items.length;
      if (items.length < pageSize) break;
    }
    return hasPulledChanges;
  }
}
