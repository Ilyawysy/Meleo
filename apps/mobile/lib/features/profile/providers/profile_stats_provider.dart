import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/profile_stats_api.dart';
import '../models/profile_stats.dart';

class ProfileStatsNotifier extends AsyncNotifier<ProfileStats?> {
  @override
  Future<ProfileStats?> build() async {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return null;
    }

    return ProfileStatsApi().getStats();
  }

  Future<void> refresh() async {
    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      state = const AsyncValue.data(null);
      return;
    }
    state = await AsyncValue.guard(() => ProfileStatsApi().getStats());
  }
}

final profileStatsProvider =
    AsyncNotifierProvider<ProfileStatsNotifier, ProfileStats?>(
  ProfileStatsNotifier.new,
  dependencies: [domainScopeToken],
);
