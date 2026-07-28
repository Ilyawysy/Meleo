import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/adaptive_plan_api.dart';
import '../models/adaptive_plan.dart';

class AdaptivePlanNotifier extends AsyncNotifier<AdaptivePlan> {
  @override
  Future<AdaptivePlan> build() async {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return const AdaptivePlan.empty();
    }

    return AdaptivePlanApi().getPlan();
  }

  Future<void> refresh() async {
    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      state = const AsyncValue.data(AdaptivePlan.empty());
      return;
    }
    state = await AsyncValue.guard(() => AdaptivePlanApi().getPlan());
  }

  Future<void> setupPlan(List<int> hoursPerDay) async {
    await updatePlan(hoursPerDay: hoursPerDay);
  }

  Future<void> startGrowth(int targetHours, GrowthSpeed speed) async {
    await updatePlan(
      growthTargetHours: targetHours,
      growthSpeed: speed,
      growthStartedAt: DateTime.now(),
    );
  }

  Future<void> stopGrowth() async {
    await updatePlan(
      clearFields: {'growth_target_hours', 'growth_speed', 'growth_started_at'},
    );
  }

  Future<void> updatePlan({
    List<int>? hoursPerDay,
    int? growthTargetHours,
    GrowthSpeed? growthSpeed,
    DateTime? growthStartedAt,
    Set<String> clearFields = const {},
  }) async {
    final updates = AdaptivePlan(
      hoursPerDay: hoursPerDay,
      growthTargetHours: growthTargetHours,
      growthSpeed: growthSpeed,
      growthStartedAt: growthStartedAt,
    );
    final result = await AsyncValue.guard(
      () => AdaptivePlanApi().patchPlan(updates, clearFields: clearFields),
    );
    state = result;
  }

  Future<void> clearPlan() async {
    await updatePlan(
      clearFields: {
        'hours_per_day',
        'growth_target_hours',
        'growth_speed',
        'growth_started_at',
      },
    );
  }
}

final adaptivePlanProvider =
    AsyncNotifierProvider<AdaptivePlanNotifier, AdaptivePlan>(
  AdaptivePlanNotifier.new,
  dependencies: [domainScopeToken],
);
