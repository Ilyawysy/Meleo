import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/notification_db.dart';
import '../models/notification.dart' as notification_model;
import '../../../core/models/recurrence.dart';

/// Reactive read provider for notifications from local DB.
///
/// Filters out sent non-recurring notifications (same logic as old
/// ShellScaffold._loadNotifications).
class NotificationsReadNotifier
    extends Notifier<AsyncValue<List<notification_model.Notification>>> {
  @override
  AsyncValue<List<notification_model.Notification>> build() {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return const AsyncValue.data([]);
    }

    _load();
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    try {
      final items = await NotificationDb().list(limit: 50, offset: 0);
      // Filter: hide sent non-recurring (already shown by system)
      final filtered = items
          .where((n) => !n.sent || n.recurrence != Recurrence.none)
          .toList();
      state = AsyncValue.data(filtered);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Refresh from local DB. Called by commands after writes
  /// and by sync callbacks. Read-only — does NOT call scheduleSync().
  Future<void> refresh() async {
    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      state = const AsyncValue.data([]);
      return;
    }
    await _load();
  }
}

final notificationsReadProvider = NotifierProvider<NotificationsReadNotifier,
    AsyncValue<List<notification_model.Notification>>>(
  NotificationsReadNotifier.new,
  dependencies: [domainScopeToken],
);
