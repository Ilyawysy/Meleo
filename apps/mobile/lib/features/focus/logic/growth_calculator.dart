import 'dart:math';

import '../models/adaptive_plan.dart';

int basePlanTotalHours(List<int>? hoursPerDay) =>
    hoursPerDay?.fold(0, (s, h) => s! + h) ?? 0;

int weeksSinceStart(DateTime startedAt, DateTime now) =>
    max(0, now.difference(startedAt).inDays ~/ 7);

int currentWeeklyTargetHours({
  required int basePlanTotal,
  required int targetTotal,
  required DateTime startedAt,
  required GrowthSpeed speed,
  required DateTime now,
}) {
  if (targetTotal <= basePlanTotal) return basePlanTotal;
  final weeks = weeksSinceStart(startedAt, now);
  final total = weeksToTarget(speed);
  final progress = min(weeks / total, 1.0);
  final add = ((targetTotal - basePlanTotal) * progress).round();
  return basePlanTotal + add;
}

DateTime estimatedCompletionDate({
  required DateTime startedAt,
  required GrowthSpeed speed,
}) =>
    startedAt.add(Duration(days: weeksToTarget(speed) * 7));

bool isGrowthCompleted({
  required int basePlanTotal,
  required int targetTotal,
  required DateTime startedAt,
  required GrowthSpeed speed,
  required DateTime now,
}) =>
    currentWeeklyTargetHours(
      basePlanTotal: basePlanTotal,
      targetTotal: targetTotal,
      startedAt: startedAt,
      speed: speed,
      now: now,
    ) >=
    targetTotal;
