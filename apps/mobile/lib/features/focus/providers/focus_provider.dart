import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/focus_db.dart';
import '../models/focus_models.dart';
import '../models/gamification_models.dart';
import '../models/focus_room_data.dart';

/// Provider for Focus domain state.
///
/// Loads cached data from FocusDb on build, session-guarded.
/// FocusTab remains StatefulWidget for timer/dialog UI state.
class FocusNotifier extends Notifier<FocusRoomData?> {
  @override
  FocusRoomData? build() {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return null;
    }

    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final focusDb = FocusDb();
      final cached = await Future.wait([
        focusDb.getBalance(),
        focusDb.getShopItems(),
        focusDb.getProfile(),
        focusDb.getActiveSession(),
        focusDb.getActiveItems(),
      ]);
      final cachedBalance = cached[0] as Balance?;
      final cachedItems = cached[1] as List<ShopItem>?;
      final cachedProfile = cached[2] as GamificationProfile?;
      final cachedSession = cached[3] as FocusSession?;
      final cachedActiveItems = cached[4] as ActiveItems?;

      debugPrint('[FOCUS_DIAG] _load: profile=${cachedProfile != null ? "level=${cachedProfile.level}, minimal=${cachedProfile.minimalMode}" : "NULL"}, balance=${cachedBalance?.coins}');
      state = FocusRoomData(
        coins: cachedBalance?.coins ?? 0.0,
        profile: cachedProfile,
        items: cachedItems ?? [],
        activeItems: cachedActiveItems ?? const ActiveItems(),
        session: cachedSession,
        sessionTask: null,
      );
    } catch (e) {
      debugPrint('[FocusNotifier] Failed to load: $e');
      state = FocusRoomData(coins: 0, error: 'Не удалось загрузить кэш: $e');
    }
  }

  /// Refresh focus data from local DB.
  /// Read-only — does NOT call scheduleSync() (sync is triggered
  /// by _load or by FocusTab after session changes).
  Future<void> refresh() async {
    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      state = null;
      return;
    }
    await _load();
  }
}

final focusProvider = NotifierProvider<FocusNotifier, FocusRoomData?>(
  FocusNotifier.new,
  dependencies: [domainScopeToken],
);
