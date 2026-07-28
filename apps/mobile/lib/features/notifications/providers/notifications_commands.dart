import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/concurrency/domain_operation_queue.dart';
import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/notification_db.dart';
import '../data/notification_sync_service.dart';
import '../models/notification.dart' as notification_model;
import '../services/local_notification_service.dart';
import 'notifications_read_provider.dart';

/// Write commands for Notifications domain.
///
/// All writes go through [DomainOperationQueue] to prevent lost updates.
/// Each write atomically updates local DB (with dirty flag = outbox intent),
/// then schedules sync, reschedules local notifications, and refreshes the
/// read provider.
class NotificationsCommands extends Notifier<void> {
  final _queue = DomainOperationQueue();
  final _db = NotificationDb();

  @override
  void build() {
    ref.watch(domainScopeToken);
  }

  bool _shouldAbort() {
    final session = ref.read(sessionScopeProvider);
    return !session.isAuthenticated || session.logoutInProgress;
  }

  void _afterWrite() {
    ref.read(notificationsReadProvider.notifier).refresh();
    NotificationSyncService.instance.scheduleSync();
  }

  /// Create a new notification.
  Future<notification_model.Notification?> createNotification({
    required String title,
    required DateTime time,
    String recurrence = 'none',
  }) async {
    if (_shouldAbort()) return null;
    return _queue.run(() async {
      final created = await _db.create(
        title: title,
        time: time,
        recurrence: recurrence,
      );
      // Schedule local OS notification
      try {
        await LocalNotificationService().scheduleNotification(created);
      } catch (e) {
        debugPrint('[NotificationsCommands] Failed to schedule: $e');
      }
      _afterWrite();
      return created;
    });
  }

  /// Update an existing notification.
  Future<notification_model.Notification?> updateNotification({
    required String id,
    required String title,
    required DateTime time,
    required String recurrence,
    bool? sent,
  }) async {
    if (_shouldAbort()) return null;
    return _queue.run(() async {
      // Cancel old local notification
      try {
        await LocalNotificationService().cancelNotification(id);
      } catch (e) {
        debugPrint('[NotificationsCommands] Failed to cancel old: $e');
      }
      final updated = await _db.update(
        id,
        title: title,
        time: time,
        recurrence: recurrence,
        sent: sent,
      );
      // Schedule new local notification
      try {
        await LocalNotificationService().scheduleNotification(updated);
      } catch (e) {
        debugPrint('[NotificationsCommands] Failed to reschedule: $e');
      }
      _afterWrite();
      return updated;
    });
  }

  /// Soft-delete a notification (marks pending_delete for sync).
  Future<void> deleteNotification(String id) async {
    if (_shouldAbort()) return;
    await _queue.run(() async {
      try {
        await LocalNotificationService().cancelNotification(id);
      } catch (e) {
        debugPrint('[NotificationsCommands] Failed to cancel: $e');
      }
      await _db.delete(id);
      _afterWrite();
    });
  }

  /// Called by editor screen returning a result.
  Future<void> handleEditorResult(
    notification_model.Notification? original,
    Object? result,
  ) async {
    if (result == null || _shouldAbort()) return;

    // Handle delete action
    if (result is Map && result['action'] == 'delete' && original != null) {
      await deleteNotification(original.id);
      return;
    }

    // Otherwise treat as Notification (create or update)
    final edited = result as notification_model.Notification;
    if (original == null) {
      // Create
      await createNotification(
        title: edited.title,
        time: edited.time,
        recurrence: edited.recurrence.name,
      );
    } else {
      // Update
      await updateNotification(
        id: original.id,
        title: edited.title,
        time: edited.time,
        recurrence: edited.recurrence.name,
      );
    }
  }
}

final notificationsCommandsProvider =
    NotifierProvider<NotificationsCommands, void>(
  NotificationsCommands.new,
  dependencies: [domainScopeToken],
);
