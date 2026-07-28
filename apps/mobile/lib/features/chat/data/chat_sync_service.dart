import 'dart:async';
import 'dart:developer' as developer;
import '../../../core/sentry_config.dart';
import '../../auth/data/token_manager.dart';
import 'chat_db.dart';
import 'chat_api.dart';

class ChatSyncService {
  ChatSyncService._();
  static final ChatSyncService instance = ChatSyncService._();

  bool _syncInProgress = false;
  Timer? _debounce;
  void Function()? onSyncComplete;

  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
  }

  // Public helper to request a near-future background sync after local writes
  void scheduleSync({Duration delay = const Duration(seconds: 2)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, _maybeSync);
  }

  Future<void> _maybeSync() async {
    if (_syncInProgress) return;
    if (!(await TokenManager.isAuthenticated)) return; // need token to talk to server
    _syncInProgress = true;
    bool success = false;
    try {
      await _syncDirtyThreads();
      await _syncDirtyMessages();
      success = true;
    } catch (e, stackTrace) {
      developer.log(
        '❌ [ChatSyncService] Sync failed: ${e.runtimeType} $e',
        name: 'ChatSyncService',
        error: e,
        stackTrace: stackTrace,
      );
      SentryConfig.addBreadcrumb(
        message: 'Chat sync failed',
        category: 'sync.chat',
        level: SentryLevel.error,
        criticalOnly: true, // Critical for prod
        data: {
          'error': e.toString(),
          'error_type': e.runtimeType.toString(),
        },
      );
      if (TokenManager.isAuthError(e)) {
        await TokenManager.handleAuthFailure(e);
        developer.log(
          '⚠️ [ChatSyncService] Auth error handled (token cleared)',
          name: 'ChatSyncService',
        );
        SentryConfig.addBreadcrumb(
          message: 'Auth error during chat sync',
          category: 'sync.chat',
          level: SentryLevel.warning,
          criticalOnly: true, // Critical for prod
        );
      }
    } finally {
      _syncInProgress = false;
      if (success) onSyncComplete?.call();
    }
  }

  Future<bool> syncNowFull() async {
    if (!(await TokenManager.isAuthenticated)) return false;
    final pulledChanges = await _pullAllThreads();
    final dirtyThreadChanges = await _syncDirtyThreads();
    final dirtyMessageChanges = await _syncDirtyMessages();
    return pulledChanges || dirtyThreadChanges || dirtyMessageChanges;
  }

  Future<bool> _pullAllThreads() async {
    final api = ChatApi();
    final db = ChatDb();
    const pageSize = 100;
    var offset = 0;
    var hasPulledChanges = false;
    while (true) {
      final items = await api.listThreads(limit: pageSize, offset: offset);
      if (items.isEmpty) break;
      for (final t in items) {
        final changed = await db.upsertThreadFromRemote(t);
        hasPulledChanges = hasPulledChanges || changed;
      }
      offset += items.length;
      if (items.length < pageSize) break;
    }
    return hasPulledChanges;
  }

  Future<bool> _syncDirtyThreads() async {
    final db = ChatDb();
    final api = ChatApi();
    final rows = await db.dirtyThreads();
    final hasDirtyRows = rows.isNotEmpty;

    // Group by operation type
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

    // Process deletes
    for (final row in deletes) {
      try {
        final localId = row['id'] as String;
        final remoteId = row['remote_id'] as String?;
        if (remoteId != null && remoteId.isNotEmpty) {
          await api.deleteThread(remoteId);
        }
        await db.deleteThreadHard(localId);
      } catch (_) {
        // Keep dirty; will retry later
      }
    }

    // Process creates
    for (final row in creates) {
      try {
        final localId = row['id'] as String;
        final title = (row['title'] as String?) ?? 'New Chat';

        final created = await api.createThread(title: title);
        await db.setThreadSynced(localId, remoteId: created.remoteId ?? created.id);
      } catch (_) {
        // Keep dirty; will retry later
      }
    }

    // Process updates
    for (final row in updates) {
      try {
        final localId = row['id'] as String;
        final remoteId = row['remote_id'] as String?;
        if (remoteId == null || remoteId.isEmpty) continue;
        final title = row['title'] as String?;

        if (title != null) {
          await api.getThread(remoteId); // Just verify it exists
          // Note: Backend doesn't have update thread endpoint, so we skip update
        }
        await db.setThreadClean(localId);
      } catch (_) {
        // Keep dirty; will retry later
      }
    }
    return hasDirtyRows;
  }

  Future<bool> _syncDirtyMessages() async {
    final db = ChatDb();
    final api = ChatApi();
    final rows = await db.dirtyMessages();
    final hasDirtyRows = rows.isNotEmpty;

    // Group by operation type
    final List<Map<String, Object?>> deletes = [];
    final List<Map<String, Object?>> creates = [];

    for (final row in rows) {
      final isPendingDelete = (row['pending_delete'] as int? ?? 0) == 1;
      final remoteId = row['remote_id'] as String?;
      final threadId = row['thread_id'] as String;

      // Get thread to find remote_id
      final thread = await db.getThread(threadId);
      if (thread == null || thread.remoteId == null) {
        // Thread not synced yet, skip message sync
        continue;
      }

      if (isPendingDelete) {
        deletes.add(row);
      } else if (remoteId == null || remoteId.isEmpty) {
        creates.add(row);
      }
    }

    // Process deletes (messages are usually not deleted individually, but handle it)
    for (final row in deletes) {
      try {
        final localId = row['id'] as String;
        // Messages deletion is handled by thread deletion on backend
        await db.deleteMessage(localId);
      } catch (_) {
        // Keep dirty; will retry later
      }
    }

    // Process creates in batches
    if (creates.isNotEmpty) {
      await _processBatches<Map<String, Object?>>(creates, (row) async {
        try {
          final localId = row['id'] as String;
          final threadId = row['thread_id'] as String;
          final text = row['text'] as String;
          final isMe = (row['is_me'] as int? ?? 0) == 1;

          final thread = await db.getThread(threadId);
          if (thread == null || thread.remoteId == null) {
            return; // Thread not synced yet
          }

          final created = await api.addMessage(
            threadId: thread.remoteId!,
            role: isMe ? 'user' : 'assistant',
            content: text,
          );
          await db.setMessageSynced(localId, remoteId: created.remoteId ?? created.id);
        } catch (_) {
          // Keep dirty; will retry later
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

  // Pull messages for a specific thread
  Future<void> pullThreadMessages(String threadId) async {
    final db = ChatDb();
    final api = ChatApi();
    final thread = await db.getThread(threadId);
    if (thread == null || thread.remoteId == null) return;

    const pageSize = 100;
    var offset = 0;
    while (true) {
      final items = await api.listMessages(
        threadId: thread.remoteId!,
        limit: pageSize,
        offset: offset,
      );
      if (items.isEmpty) break;
      for (final m in items) {
        await db.upsertMessageFromRemote(m, threadId);
      }
      offset += items.length;
      if (items.length < pageSize) break;
    }
  }
}
