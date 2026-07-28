import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_orchestrator.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/notifications/services/local_notification_service.dart';
import '../../core/database/database_provider.dart';
import '../../core/preferences/filter_preferences.dart';
import '../../core/preferences/settings_preferences.dart';
import 'session_scope.dart';
import 'app_scope_controller.dart';

/// Координирует полное завершение пользовательской сессии.
///
/// 1. logoutInProgress=true in SessionScope
/// 2. SyncOrchestrator.stopAndResetAll() (await)
/// 3. stop local notifications
/// 4. rotate Inner ProviderScope key (hard reset domain container)
/// 5. clear local DB/preferences
/// 6. auth logout (best-effort, with timeout; errors don't block local exit)
/// 7. sessionEpoch++, userId=null, isAuthenticated=false, logoutInProgress=false
class LogoutController extends Notifier<void> {
  @override
  void build() {}

  Future<void> logout() async {
    final session = ref.read(sessionScopeProvider.notifier);

    // 1. Mark logout in progress — domain guards will block new loads.
    session.beginLogout();
    debugPrint('[LogoutController] step 1: logoutInProgress=true');

    // 2. Stop all sync services.
    await SyncOrchestrator.instance.stopAndResetAll();
    debugPrint('[LogoutController] step 2: sync stopped');

    // 3. Stop local notifications.
    LocalNotificationService().stop();
    debugPrint('[LogoutController] step 3: local notifications stopped');

    // 4. Rotate Inner ProviderScope key — destroys domain providers.
    ref.read(appScopeControllerProvider.notifier).rotate();
    debugPrint('[LogoutController] step 4: inner scope rotated');

    // 5. Clear local DB and preferences.
    // Onboarding prefs are intentionally NOT cleared: they are keyed by userId,
    // so they remain valid for the same user on re-login and do not leak to
    // other accounts. Clearing them forces a repeated onboarding whenever the
    // user logs out and back in before the sync-based resolution completes.
    try {
      await DatabaseProvider().clearAllOnLogout();
      await FilterPreferences.clearAll();
      await SettingsPreferences.clearAll();
      debugPrint('[LogoutController] step 5: DB/prefs cleared');
    } catch (e) {
      debugPrint('[LogoutController] step 5: clear failed (ignored): $e');
    }

    // 6. Auth logout — best-effort with timeout.
    try {
      await AuthService()
          .logout()
          .timeout(const Duration(seconds: 5));
      debugPrint('[LogoutController] step 6: auth logout ok');
    } catch (e) {
      debugPrint('[LogoutController] step 6: auth logout failed (ignored): $e');
    }

    // 7. Finalize session state.
    session.completeLogout();
    debugPrint('[LogoutController] step 7: session cleared');
  }
}

final logoutControllerProvider =
    NotifierProvider<LogoutController, void>(
  LogoutController.new,
);
