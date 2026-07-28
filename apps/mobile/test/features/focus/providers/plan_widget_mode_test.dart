import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/features/focus/models/adaptive_plan.dart';
import 'package:meleo/features/focus/models/focus_room.dart';
import 'package:meleo/features/focus/providers/plan_widget_mode_provider.dart';

FocusRoom _room({
  String id = 'r1',
  FocusRoomType type = FocusRoomType.regular,
  bool archived = false,
  DateTime? sprintDeadline,
}) {
  final now = DateTime(2025, 6, 1);
  return FocusRoom(
    id: id,
    title: 'Room',
    color: '#6366F1',
    type: type,
    archived: archived,
    sprintDeadline: sprintDeadline,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final now = DateTime(2025, 6, 1, 12, 0, 0);

  group('computePlanWidgetMode', () {
    test('empty: plan=null, no rooms', () {
      expect(
        computePlanWidgetMode(rooms: [], plan: null, now: now),
        PlanWidgetMode.empty,
      );
    });

    test('empty: plan=null, only regular rooms', () {
      expect(
        computePlanWidgetMode(
          rooms: [_room()],
          plan: null,
          now: now,
        ),
        PlanWidgetMode.empty,
      );
    });

    test('sprint: active sprint room + plan present -> sprint wins', () {
      final plan = AdaptivePlan(
        hoursPerDay: [2, 2, 2, 2, 2, 2, 2],
        growthTargetHours: 20,
        growthSpeed: GrowthSpeed.push,
        growthStartedAt: now.subtract(const Duration(days: 1)),
      );
      final sprintRoom = _room(
        type: FocusRoomType.sprint,
        sprintDeadline: now.add(const Duration(days: 30)),
      );
      expect(
        computePlanWidgetMode(rooms: [sprintRoom], plan: plan, now: now),
        PlanWidgetMode.sprint,
      );
    });

    test('sprint: null deadline counts as active', () {
      final sprintRoom = _room(type: FocusRoomType.sprint);
      expect(
        computePlanWidgetMode(rooms: [sprintRoom], plan: null, now: now),
        PlanWidgetMode.sprint,
      );
    });

    test('sprint with expired deadline is ignored -> falls to growth', () {
      final expiredSprint = _room(
        type: FocusRoomType.sprint,
        sprintDeadline: now.subtract(const Duration(days: 1)),
      );
      final plan = AdaptivePlan(
        hoursPerDay: [1, 1, 1, 1, 1, 1, 1],
        growthTargetHours: 20,
        growthSpeed: GrowthSpeed.push,
        growthStartedAt: now.subtract(const Duration(days: 1)),
      );
      expect(
        computePlanWidgetMode(rooms: [expiredSprint], plan: plan, now: now),
        PlanWidgetMode.growth,
      );
    });

    test('sprint with expired deadline is ignored -> falls to plan', () {
      final expiredSprint = _room(
        type: FocusRoomType.sprint,
        sprintDeadline: now.subtract(const Duration(days: 1)),
      );
      final plan = AdaptivePlan(hoursPerDay: [2, 2, 2, 2, 2, 2, 2]);
      expect(
        computePlanWidgetMode(rooms: [expiredSprint], plan: plan, now: now),
        PlanWidgetMode.plan,
      );
    });

    test('sprint with expired deadline is ignored -> falls to empty', () {
      final expiredSprint = _room(
        type: FocusRoomType.sprint,
        sprintDeadline: now.subtract(const Duration(days: 1)),
      );
      expect(
        computePlanWidgetMode(rooms: [expiredSprint], plan: null, now: now),
        PlanWidgetMode.empty,
      );
    });

    test('archived sprint room is ignored -> falls to plan', () {
      final archivedSprint = _room(
        type: FocusRoomType.sprint,
        archived: true,
      );
      final plan = AdaptivePlan(hoursPerDay: [1, 2, 3, 0, 0, 0, 0]);
      expect(
        computePlanWidgetMode(rooms: [archivedSprint], plan: plan, now: now),
        PlanWidgetMode.plan,
      );
    });

    test('growth: target > basePlan, not completed -> growth', () {
      // basePlan = 7 (1h/day * 7 days), target = 14, speed=push(2 weeks)
      // started 1 day ago -> 0 weeks -> not completed
      final plan = AdaptivePlan(
        hoursPerDay: [1, 1, 1, 1, 1, 1, 1],
        growthTargetHours: 14,
        growthSpeed: GrowthSpeed.push,
        growthStartedAt: now.subtract(const Duration(days: 1)),
      );
      expect(
        computePlanWidgetMode(rooms: [], plan: plan, now: now),
        PlanWidgetMode.growth,
      );
    });

    test('growth ignored: target <= basePlan -> falls to plan', () {
      // basePlan = 14, target = 10 (<= base) -> guard fires, skip growth
      final plan = AdaptivePlan(
        hoursPerDay: [2, 2, 2, 2, 2, 2, 2],
        growthTargetHours: 10,
        growthSpeed: GrowthSpeed.push,
        growthStartedAt: now.subtract(const Duration(days: 1)),
      );
      expect(
        computePlanWidgetMode(rooms: [], plan: plan, now: now),
        PlanWidgetMode.plan,
      );
    });

    test('growth ignored: target == basePlan -> falls to plan', () {
      final plan = AdaptivePlan(
        hoursPerDay: [2, 2, 2, 2, 2, 2, 2],
        growthTargetHours: 14,
        growthSpeed: GrowthSpeed.push,
        growthStartedAt: now.subtract(const Duration(days: 1)),
      );
      expect(
        computePlanWidgetMode(rooms: [], plan: plan, now: now),
        PlanWidgetMode.plan,
      );
    });

    test('plan: hoursPerDay with >0 values, no growth, no sprint -> plan', () {
      final plan = AdaptivePlan(hoursPerDay: [0, 2, 0, 0, 0, 0, 0]);
      expect(
        computePlanWidgetMode(rooms: [], plan: plan, now: now),
        PlanWidgetMode.plan,
      );
    });

    test('all zeros in hoursPerDay -> empty', () {
      final plan = AdaptivePlan(hoursPerDay: [0, 0, 0, 0, 0, 0, 0]);
      expect(
        computePlanWidgetMode(rooms: [], plan: plan, now: now),
        PlanWidgetMode.empty,
      );
    });
  });
}
