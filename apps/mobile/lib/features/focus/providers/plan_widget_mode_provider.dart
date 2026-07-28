import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../logic/growth_calculator.dart';
import '../models/adaptive_plan.dart';
import '../models/focus_room.dart';
import 'adaptive_plan_provider.dart';
import 'focus_rooms_provider.dart';

PlanWidgetMode computePlanWidgetMode({
  required List<FocusRoom> rooms,
  required AdaptivePlan? plan,
  required DateTime now,
}) {
  // 1. Active sprint room? -> sprint
  // Active sprint: type==sprint, !archived, deadline is null or in the future
  final sprintRooms = rooms
      .where(
        (r) =>
            r.type == FocusRoomType.sprint &&
            !r.archived &&
            (r.sprintDeadline == null || r.sprintDeadline!.isAfter(now)),
      )
      .toList();

  if (sprintRooms.isNotEmpty) {
    return PlanWidgetMode.sprint;
  }

  // 2. Growth mode: plan has target+start, growth not yet completed, target > basePlanTotal
  if (plan != null &&
      plan.growthTargetHours != null &&
      plan.growthStartedAt != null &&
      plan.growthSpeed != null) {
    final base = basePlanTotalHours(plan.hoursPerDay);
    if (plan.growthTargetHours! > base) {
      final completed = isGrowthCompleted(
        basePlanTotal: base,
        targetTotal: plan.growthTargetHours!,
        startedAt: plan.growthStartedAt!,
        speed: plan.growthSpeed!,
        now: now,
      );
      if (!completed) {
        return PlanWidgetMode.growth;
      }
    }
  }

  // 3. plan with active hours -> plan
  if (plan != null && (plan.hoursPerDay?.any((h) => h > 0) ?? false)) {
    return PlanWidgetMode.plan;
  }

  // 4. empty
  return PlanWidgetMode.empty;
}

final planWidgetModeProvider = Provider<PlanWidgetMode>(
  (ref) {
    ref.watch(domainScopeToken);
    final rooms = ref.watch(focusRoomsProvider).valueOrNull ?? const [];
    final plan = ref.watch(adaptivePlanProvider).valueOrNull;
    return computePlanWidgetMode(
      rooms: rooms,
      plan: plan,
      now: DateTime.now(),
    );
  },
  dependencies: [domainScopeToken, focusRoomsProvider, adaptivePlanProvider],
);
