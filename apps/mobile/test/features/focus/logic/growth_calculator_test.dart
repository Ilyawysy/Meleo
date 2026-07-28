import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/features/focus/logic/growth_calculator.dart';
import 'package:meleo/features/focus/models/adaptive_plan.dart';

void main() {
  group('basePlanTotalHours', () {
    test('null hoursPerDay returns 0', () {
      expect(basePlanTotalHours(null), 0);
    });

    test('sums all hours', () {
      expect(basePlanTotalHours([1, 2, 3, 0, 0, 1, 1]), 8);
    });
  });

  group('weeksSinceStart', () {
    test('zero days diff returns 0', () {
      final now = DateTime(2025, 1, 1);
      expect(weeksSinceStart(now, now), 0);
    });

    test('6 days is still 0 weeks', () {
      final start = DateTime(2025, 1, 1);
      final now = DateTime(2025, 1, 7);
      expect(weeksSinceStart(start, now), 0);
    });

    test('7 days is 1 week', () {
      final start = DateTime(2025, 1, 1);
      final now = DateTime(2025, 1, 8);
      expect(weeksSinceStart(start, now), 1);
    });

    test('future start returns 0 (clamped)', () {
      final start = DateTime(2025, 6, 1);
      final now = DateTime(2025, 1, 1);
      expect(weeksSinceStart(start, now), 0);
    });
  });

  group('weeksToTarget', () {
    test('steady = 6', () => expect(weeksToTarget(GrowthSpeed.steady), 6));
    test('faster = 4', () => expect(weeksToTarget(GrowthSpeed.faster), 4));
    test('push = 2', () => expect(weeksToTarget(GrowthSpeed.push), 2));
  });

  group('currentWeeklyTargetHours', () {
    final start = DateTime(2025, 1, 1);

    test('zero progress returns basePlanTotal', () {
      final result = currentWeeklyTargetHours(
        basePlanTotal: 10,
        targetTotal: 20,
        startedAt: start,
        speed: GrowthSpeed.steady,
        now: start,
      );
      expect(result, 10);
    });

    test('half progress interpolates correctly (steady=6 weeks, 3 weeks in)', () {
      final now = start.add(const Duration(days: 21)); // 3 weeks
      final result = currentWeeklyTargetHours(
        basePlanTotal: 10,
        targetTotal: 20,
        startedAt: start,
        speed: GrowthSpeed.steady,
        now: now,
      );
      // progress = 3/6 = 0.5, add = (20-10) * 0.5 = 5
      expect(result, 15);
    });

    test('progress >= weeksToTarget clamps to target', () {
      final now = start.add(const Duration(days: 100)); // well past target
      final result = currentWeeklyTargetHours(
        basePlanTotal: 10,
        targetTotal: 20,
        startedAt: start,
        speed: GrowthSpeed.push,
        now: now,
      );
      expect(result, 20);
    });

    test('targetTotal <= basePlanTotal returns basePlanTotal', () {
      final result = currentWeeklyTargetHours(
        basePlanTotal: 20,
        targetTotal: 15,
        startedAt: start,
        speed: GrowthSpeed.faster,
        now: start.add(const Duration(days: 14)),
      );
      expect(result, 20);
    });

    test('targetTotal == basePlanTotal returns basePlanTotal', () {
      final result = currentWeeklyTargetHours(
        basePlanTotal: 10,
        targetTotal: 10,
        startedAt: start,
        speed: GrowthSpeed.push,
        now: start.add(const Duration(days: 7)),
      );
      expect(result, 10);
    });
  });

  group('estimatedCompletionDate', () {
    final start = DateTime(2025, 1, 1);

    test('steady: 6 weeks = 42 days', () {
      final result = estimatedCompletionDate(
        startedAt: start,
        speed: GrowthSpeed.steady,
      );
      expect(result, start.add(const Duration(days: 42)));
    });

    test('faster: 4 weeks = 28 days', () {
      final result = estimatedCompletionDate(
        startedAt: start,
        speed: GrowthSpeed.faster,
      );
      expect(result, start.add(const Duration(days: 28)));
    });

    test('push: 2 weeks = 14 days', () {
      final result = estimatedCompletionDate(
        startedAt: start,
        speed: GrowthSpeed.push,
      );
      expect(result, start.add(const Duration(days: 14)));
    });
  });

  group('isGrowthCompleted', () {
    final start = DateTime(2025, 1, 1);

    test('returns false when not enough time passed', () {
      expect(
        isGrowthCompleted(
          basePlanTotal: 10,
          targetTotal: 20,
          startedAt: start,
          speed: GrowthSpeed.push,
          now: start.add(const Duration(days: 7)),
        ),
        false,
      );
    });

    test('returns true when target reached', () {
      expect(
        isGrowthCompleted(
          basePlanTotal: 10,
          targetTotal: 20,
          startedAt: start,
          speed: GrowthSpeed.push,
          now: start.add(const Duration(days: 14)),
        ),
        true,
      );
    });
  });
}
