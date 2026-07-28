import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/focus_room_sync_service.dart';
import '../data/task_db.dart';
import '../models/task.dart';
import 'focus_rooms_provider.dart';

class RoomTasksNotifier extends FamilyAsyncNotifier<List<Task>, String> {
  @override
  Future<List<Task>> build(String arg) async {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return [];
    }

    return FocusTaskDb().listForRoom(arg);
  }

  Future<void> refresh() async {
    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      state = const AsyncValue.data([]);
      return;
    }
    state = await AsyncValue.guard(() => FocusTaskDb().listForRoom(arg));
  }

  Future<void> addTask(String title) async {
    final existing = state.valueOrNull ?? [];
    final task = Task.create(
      roomId: arg,
      title: title,
      sortOrder: existing.length,
    );
    await FocusTaskDb().create(task);
    FocusRoomSyncService.instance.scheduleSync();
    ref.invalidate(focusRoomsProvider);
    await refresh();
  }

  Future<void> toggleTask(Task task) async {
    final newStatus =
        task.isDone ? TaskStatus.notDone : TaskStatus.done;
    final updated = task.copyWith(
      status: newStatus,
      completedAt: newStatus == TaskStatus.done ? DateTime.now() : null,
    );
    await FocusTaskDb().update(updated);
    FocusRoomSyncService.instance.scheduleSync();
    ref.invalidate(focusRoomsProvider);
    await refresh();
  }

  Future<void> deleteTask(String taskId) async {
    await FocusTaskDb().softDelete(taskId);
    FocusRoomSyncService.instance.scheduleSync();
    ref.invalidate(focusRoomsProvider);
    await refresh();
  }
}

final roomTasksProvider =
    AsyncNotifierProviderFamily<RoomTasksNotifier, List<Task>, String>(
  RoomTasksNotifier.new,
  dependencies: [domainScopeToken],
);
