import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/features/focus/models/focus_room.dart';
import 'package:meleo/features/focus/models/task.dart' as focus_task;

void main() {
  group('FocusRoom model', () {
    test('fromJson / toJson round-trip', () {
      final now = DateTime.utc(2025, 4, 21, 10, 0, 0);
      final json = {
        'id': 'room-1',
        'title': 'My Room',
        'color': '#FF0000',
        'type': 'sprint',
        'archived': false,
        'archived_at': null,
        'sort_order': 2,
        'sprint_goal': 'Ship it',
        'sprint_deadline': now.toIso8601String(),
        'sprint_total_hours': 40,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final room = FocusRoom.fromJson(json);
      expect(room.id, 'room-1');
      expect(room.title, 'My Room');
      expect(room.color, '#FF0000');
      expect(room.type, FocusRoomType.sprint);
      expect(room.archived, false);
      expect(room.sortOrder, 2);
      expect(room.sprintGoal, 'Ship it');
      expect(room.sprintTotalHours, 40);

      final back = room.toJson();
      expect(back['id'], 'room-1');
      expect(back['type'], 'sprint');
      expect(back['sprint_goal'], 'Ship it');
    });

    test('fromDb / toDb round-trip', () {
      final now = DateTime.utc(2025, 4, 21);
      final row = <String, Object?>{
        'id': 'room-2',
        'title': 'Sprint Room',
        'color': '#00FF00',
        'type': 'regular',
        'archived': 0,
        'archived_at': null,
        'sort_order': 0,
        'sprint_goal': null,
        'sprint_deadline': null,
        'sprint_total_hours': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'task_count': 3,
        'total_focus_sec': 1200,
      };
      final room = FocusRoom.fromDb(row);
      expect(room.id, 'room-2');
      expect(room.archived, false);
      expect(room.taskCount, 3);
      expect(room.totalFocusSec, 1200);

      final db = room.toDb();
      expect(db['id'], 'room-2');
      expect(db['archived'], 0);
      expect(db.containsKey('task_count'), false);
    });

    test('copyWith', () {
      final now = DateTime.now();
      final room = FocusRoom(
        id: 'r1',
        title: 'Old Title',
        color: '#000',
        createdAt: now,
        updatedAt: now,
      );
      final updated = room.copyWith(title: 'New Title', archived: true);
      expect(updated.title, 'New Title');
      expect(updated.archived, true);
      expect(updated.id, 'r1');
    });
  });

  group('focus Task model', () {
    test('fromJson / toJson round-trip', () {
      final now = DateTime.utc(2025, 4, 21);
      final json = {
        'id': 'task-1',
        'room_id': 'room-1',
        'title': 'Do the thing',
        'description': 'Details',
        'status': 'done',
        'sort_order': 1,
        'completed_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final task = focus_task.Task.fromJson(json);
      expect(task.id, 'task-1');
      expect(task.roomId, 'room-1');
      expect(task.status, focus_task.TaskStatus.done);
      expect(task.isDone, true);

      final back = task.toJson();
      expect(back['status'], 'done');
      expect(back['room_id'], 'room-1');
    });

    test('fromDb / toDb round-trip', () {
      final now = DateTime.utc(2025, 4, 21);
      final row = <String, Object?>{
        'id': 'task-2',
        'room_id': 'room-1',
        'title': 'Another task',
        'description': null,
        'status': 'not_done',
        'sort_order': 0,
        'completed_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final task = focus_task.Task.fromDb(row);
      expect(task.status, focus_task.TaskStatus.notDone);
      expect(task.isDone, false);

      final db = task.toDb();
      expect(db['status'], 'not_done');
    });

    test('copyWith preserves unchanged fields', () {
      final now = DateTime.now();
      final task = focus_task.Task(
        id: 't1',
        roomId: 'r1',
        title: 'Title',
        createdAt: now,
        updatedAt: now,
      );
      final updated = task.copyWith(status: focus_task.TaskStatus.done);
      expect(updated.status, focus_task.TaskStatus.done);
      expect(updated.title, 'Title');
      expect(updated.roomId, 'r1');
    });
  });
}
