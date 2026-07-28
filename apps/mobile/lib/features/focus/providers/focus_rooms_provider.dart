import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/focus_room_db.dart';
import '../data/focus_room_sync_service.dart';
import '../models/focus_room.dart';

class FocusRoomsNotifier extends AsyncNotifier<List<FocusRoom>> {
  @override
  Future<List<FocusRoom>> build() async {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return [];
    }

    return _load();
  }

  Future<List<FocusRoom>> _load() async {
    final db = FocusRoomDb();
    final rooms = await db.listForUser(archived: false);
    // Populate task count and total focus sec for each room
    final enriched = await Future.wait(rooms.map((r) async {
      final taskCount = await db.getTaskCount(r.id);
      final totalFocusSec = await db.getTotalFocusSec(r.id);
      return r.copyWith(taskCount: taskCount, totalFocusSec: totalFocusSec);
    }));
    return enriched;
  }

  Future<void> refresh() async {
    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      state = const AsyncValue.data([]);
      return;
    }
    state = await AsyncValue.guard(_load);
  }

  Future<FocusRoom> addRoom({
    required String title,
    String color = '#6366F1',
    FocusRoomType type = FocusRoomType.regular,
    String? sprintGoal,
    DateTime? sprintDeadline,
    int? sprintTotalHours,
    int? focusDurationMin,
    int? breakMin,
  }) async {
    final room = FocusRoom.create(title: title, color: color).copyWith(
      type: type,
      sprintGoal: sprintGoal,
      sprintDeadline: sprintDeadline,
      sprintTotalHours: sprintTotalHours,
      focusDurationMin: focusDurationMin,
      breakMin: breakMin,
    );
    await FocusRoomDb().create(room);
    FocusRoomSyncService.instance.scheduleSync();
    await refresh();
    return room;
  }

  Future<void> renameRoom(String roomId, String title) async {
    final rooms = state.valueOrNull ?? [];
    final room = rooms.firstWhere(
      (r) => r.id == roomId,
      orElse: () => throw StateError('room $roomId not found'),
    );
    final updated = room.copyWith(title: title, updatedAt: DateTime.now());
    await FocusRoomDb().update(updated);
    FocusRoomSyncService.instance.scheduleSync();
    await refresh();
  }

  Future<void> archiveRoom(String roomId) async {
    await FocusRoomDb().archive(roomId);
    FocusRoomSyncService.instance.scheduleSync();
    await refresh();
  }

  Future<void> unarchiveRoom(String roomId) async {
    await FocusRoomDb().unarchive(roomId);
    FocusRoomSyncService.instance.scheduleSync();
    await refresh();
  }
}

final focusRoomsProvider =
    AsyncNotifierProvider<FocusRoomsNotifier, List<FocusRoom>>(
  FocusRoomsNotifier.new,
  dependencies: [domainScopeToken],
);

// Provider for archived rooms list
final archivedRoomsProvider = FutureProvider.autoDispose<List<FocusRoom>>(
  (ref) async {
    final db = FocusRoomDb();
    final rooms = await db.listForUser(archived: true);
    final enriched = await Future.wait(rooms.map((r) async {
      final taskCount = await db.getTaskCount(r.id);
      final totalFocusSec = await db.getTotalFocusSec(r.id);
      return r.copyWith(taskCount: taskCount, totalFocusSec: totalFocusSec);
    }));
    return enriched;
  },
);
