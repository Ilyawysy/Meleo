import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/inner_scope.dart';
import '../providers/session_scope.dart';
import '../../features/notifications/data/notification_sync_service.dart';
import '../../features/chat/data/chat_sync_service.dart';
import '../../features/focus/data/focus_db.dart';
import '../../features/focus/data/focus_sync_service.dart';
import '../../features/focus/data/focus_room_sync_service.dart';
import '../../features/notifications/providers/notifications_read_provider.dart';
import '../../features/chat/providers/chat_read_provider.dart';
import '../../features/chat/providers/chat_commands.dart';
import '../../features/focus/providers/active_room_provider.dart';
import '../../features/focus/providers/adaptive_plan_provider.dart';
import '../../features/focus/providers/focus_provider.dart';
import '../../features/focus/providers/focus_rooms_provider.dart';
import '../../features/notifications/services/local_notification_service.dart';
import '../../features/subscription/providers/subscription_provider.dart';
import '../../features/statistics/providers/statistics_provider.dart';
import 'sync_orchestrator.dart';

class SyncBridgeNotifier extends Notifier<void> {
  @override
  void build() {
    ref.watch(domainScopeToken);

    // Watch (not read) sessionScopeProvider so build() re-runs when auth
    // state changes — e.g. after login when updateAuth(isAuthenticated: true)
    // fires from the onAuthStateChange listener.
    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) return;

    final userId = session.userId;
    if (userId == null || userId.isEmpty) return;

    NotificationSyncService.instance.onSyncComplete =
        _onNotificationSyncComplete;
    ChatSyncService.instance.onSyncComplete = _onChatSyncComplete;
    FocusSyncService.instance.onSyncComplete = _onFocusSyncComplete;
    FocusRoomSyncService.instance.onSyncComplete = _onFocusRoomSyncComplete;

    unawaited(ref.read(chatCommandsProvider.notifier).initChatThread());
    // Load subscription from cached DB immediately so UI
    // can render pro/free state before sync completes (warm restart).
    unawaited(ref.read(subscriptionProvider.notifier).loadFromDb());
    // Load statistics from cached DB (will show stale data until sync refreshes).
    // Deferred to avoid modifying statisticsProvider during this provider's build().
    Future.microtask(() => ref.read(statisticsProvider.notifier).refresh());
    SyncOrchestrator.instance.startAll(
      userId: userId,
      sessionEpoch: session.sessionEpoch,
    );
    unawaited(LocalNotificationService().initialize());

    ref.onDispose(() {
      NotificationSyncService.instance.onSyncComplete = null;
      ChatSyncService.instance.onSyncComplete = null;
      FocusSyncService.instance.onSyncComplete = null;
      FocusRoomSyncService.instance.onSyncComplete = null;
      unawaited(SyncOrchestrator.instance.stopAndResetAll());
    });
  }

  void _onFocusRoomSyncComplete() {
    // Sync delivered fresh focus_rooms (and implicitly tasks/checklists which
    // go through the same applyRemoteRooms path). Re-read from DB + refresh
    // the adaptive-plan endpoint so the Start tab is populated after a cold
    // login (where local DB was cleared by logout).
    // ignore: avoid_print
    print('[DIAG] SyncBridge._onFocusRoomSyncComplete: refreshing providers');
    ref.read(focusRoomsProvider.notifier).refresh();
    ref.read(adaptivePlanProvider.notifier).refresh();
    unawaited(ref.read(activeRoomIdProvider.notifier).tryResolvePending());
  }

  void _onNotificationSyncComplete() {
    ref.read(notificationsReadProvider.notifier).refresh();
  }

  void _onChatSyncComplete() {
    final chatState = ref.read(chatReadProvider);
    if (chatState.currentThreadId == null) {
      unawaited(ref.read(chatCommandsProvider.notifier).initChatThread());
    } else {
      ref.read(chatReadProvider.notifier).refresh();
    }
    ref.read(chatReadProvider.notifier).refreshChatsCount();
  }

  void _onFocusSyncComplete() {
    ref.read(focusProvider.notifier).refresh();
    // Rooms list shows per-room totalFocusSec aggregated from local sessions —
    // refresh after sync so newly-arrived sessions update the room cards.
    ref.read(focusRoomsProvider.notifier).refresh();
    // Reload statistics from local DB — sync delivered fresh daily_stats + profile.
    ref.read(statisticsProvider.notifier).refresh();
    ref.read(subscriptionProvider.notifier).loadFromDb();
    unawaited(_applyActiveRoomFromProfile());
  }

  Future<void> _applyActiveRoomFromProfile() async {
    final focusDb = FocusDb();
    final profile = await focusDb.getProfile();
    if (profile == null) return;
    final remoteId = profile.activeFocusRoomId;
    await ref.read(activeRoomIdProvider.notifier).applyFromSync(remoteId);
  }
}

final syncBridgeProvider = NotifierProvider<SyncBridgeNotifier, void>(
  SyncBridgeNotifier.new,
  dependencies: [
    domainScopeToken,
    chatCommandsProvider,
    chatReadProvider,
    notificationsReadProvider,
    focusProvider,
    focusRoomsProvider,
    activeRoomIdProvider,
    adaptivePlanProvider,
    statisticsProvider,
  ],
);
