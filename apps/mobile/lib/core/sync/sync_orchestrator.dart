import 'dart:async';
import 'dart:developer' as developer;

import '../api_http_exception.dart';
import 'aggregated_sync_service.dart';
import 'adaptive_sync_controller.dart';
import 'backoff_strategy.dart';
import 'sync_version_store.dart';
import 'sync_versions_api.dart';
import '../../features/chat/data/chat_sync_service.dart';
import '../../features/notifications/data/notification_sync_service.dart';
import '../../features/focus/data/focus_sync_service.dart';
import '../../features/focus/data/focus_room_sync_service.dart';

/// Central orchestrator for pull-sync and domain lifecycle.
///
/// Responsibilities:
/// - Start/stop all sync services with user-bound lifecycle.
/// - Pull sync (via /sync endpoint): app start, foreground resume.
/// - Kick-start domain push services on start (pick up dirty rows from previous session).
/// - Apply [BackoffStrategy] on errors to avoid thundering-herd.
/// - Ensure [stopAndResetAll] cancels all timers/subscriptions/queues.
///
/// Push is NOT orchestrated here — each domain sync service pushes
/// independently via its own [scheduleSync] debounce timer.
class SyncOrchestrator {
  SyncOrchestrator._();
  static final SyncOrchestrator instance = SyncOrchestrator._();

  final _backoff = BackoffStrategy();
  bool _syncInProgress = false;
  bool _started = false;
  Duration? _retryAfterDelay;

  /// Tracks the in-flight _runSync() Future so stopAndResetAll() can await it.
  Future<void>? _activeSyncFuture;

  /// Cancellable retry timer (replaced on each _scheduleRetry call).
  Timer? _retryTimer;

  String? _userId;
  int? _sessionEpoch;

  /// Callback invoked when sync confirms onboarding_completed == true.
  OnboardingCompletedFn? onOnboardingCompleted;

  /// Fires exactly once after sync returns an authoritative onboarding state.
  void Function()? onFirstSyncSettled;

  bool _firstSyncSettled = false;

  /// Start all sync services bound to [userId] and [sessionEpoch].
  void startAll({required String userId, required int sessionEpoch}) {
    if (_started) return;
    _userId = userId;
    _sessionEpoch = sessionEpoch;

    _firstSyncSettled = false;
    AggregatedSyncService.instance.reset();
    AggregatedSyncService.instance.onPagePersist =
        (DomainVersions appliedVersions, String? cursor) async {
          if (!_started) return; // skip persist if logout is in progress
          await SyncVersionStore.instance.saveVersionsAndCursor(
            appliedVersions,
            cursor,
          );
        };
    AggregatedSyncService.instance.getUserId = () => _userId;
    AggregatedSyncService.instance.onOnboardingCompleted = () {
      onOnboardingCompleted?.call();
    };

    // Lifecycle observer: sync on foreground resume
    AdaptiveSyncController.instance.start(onResume: syncNow);
    _started = true;

    // Kick-start push for all domains — pick up dirty rows left from
    // a previous session (e.g. app was killed before debounce fired).
    ChatSyncService.instance.scheduleSync(delay: Duration.zero);
    NotificationSyncService.instance.scheduleSync(delay: Duration.zero);
    FocusSyncService.instance.scheduleSync(delay: Duration.zero);
    FocusRoomSyncService.instance.scheduleSync(delay: Duration.zero);

    // Initial pull at app start
    _activeSyncFuture = _runSync();
  }

  /// Stop all sync services and reset their internal state.
  ///
  /// After this call no timers, subscriptions, or queues remain active.
  /// [_started] and [_syncInProgress] are set to false EARLY (before async
  /// cleanup) so a subsequent [startAll] call does not see stale flags.
  Future<void> stopAndResetAll() async {
    if (!_started) return;

    // Set _started=false early so in-flight _runSync() bails out at the next
    // checkpoint instead of writing to a DB that is about to be cleared.
    _started = false;
    _retryAfterDelay = null;

    // Cancel pending retry timer (prevents new _runSync() from being queued).
    _retryTimer?.cancel();
    _retryTimer = null;

    // Await the in-flight sync Future. Because _started is already false,
    // _runSync() will exit at the next checkpoint without persisting stale data.
    final pending = _activeSyncFuture;
    if (pending != null) {
      await pending;
    }
    _activeSyncFuture = null;
    _syncInProgress = false;

    _userId = null;
    _sessionEpoch = null;
    _firstSyncSettled = false;
    onFirstSyncSettled = null;

    AdaptiveSyncController.instance.stop();
    _backoff.reset();
    AggregatedSyncService.instance.reset();

    await ChatSyncService.instance.stop();
    await NotificationSyncService.instance.stop();
    await FocusSyncService.instance.stop();
    await FocusRoomSyncService.instance.stop();
    await SyncVersionStore.instance.clear();
  }

  /// Trigger an immediate sync (e.g. on foreground resume or after local mutation).
  ///
  /// Does not overwrite [_activeSyncFuture] when a sync is already in flight —
  /// otherwise stopAndResetAll() would await a no-op Future instead of the
  /// real one, re-introducing the race condition.
  void syncNow() {
    if (_syncInProgress) return;
    _activeSyncFuture = _runSync();
  }

  /// Central pull-sync cycle.
  ///
  /// 1. Pull via unified /sync (all domains in one request).
  ///    Server skips SELECTs for unchanged domains via tv/nv/mv/fv.
  /// 2. Fire callbacks for ALL domains.
  /// 3. Persist server versions + cursor atomically.
  ///
  /// Push is handled independently by each domain sync service.
  Future<void> _runSync() async {
    if (_syncInProgress) return;
    if (!_started) return;
    _syncInProgress = true;

    // If we're in backoff, wait before proceeding
    final delay = _retryAfterDelay ?? _backoff.getNextDelay();
    _retryAfterDelay = null;
    if (delay > Duration.zero) {
      developer.log(
        'Backoff: waiting ${delay.inSeconds}s before sync '
        '(failures=${_backoff.failureCount})',
        name: 'SyncOrchestrator',
      );
      await Future.delayed(delay);
      if (!_started) {
        _syncInProgress = false;
        return;
      }
    }

    try {
      // 1. Load local state (versions + cursor)
      final localVersions = await SyncVersionStore.instance.loadVersions();
      final savedCursor = await SyncVersionStore.instance.loadCursor();
      if (!_started) return; // checkpoint: bail out if stopped

      // Restore persisted cursor into service (survives app restart)
      AggregatedSyncService.instance.cursor = savedCursor;

      // 2. Pull via unified /sync (all 5 domains)
      //    ETag makes 304 cheap when nothing changed.
      //    fv/rv params let server skip SELECTs for unchanged domains.
      developer.log(
        '[DIAG] _runSync: calling aggregated sync '
        '(localVersions=${localVersions == null ? "null" : "present"}, '
        'cursor=${savedCursor == null ? "null" : "present"})',
        name: 'SyncOrchestrator',
      );
      final result = await AggregatedSyncService.instance.sync(
        reportAdaptive: false,
        localVersions: localVersions,
      );
      if (!_started) return; // checkpoint: bail out if stopped during pull

      final serverVersions = result.serverVersions;
      developer.log(
        '[DIAG] _runSync: result hasChanges=${result.hasChanges} '
        'serverVersions=${serverVersions == null ? "null" : "present"} '
        'needsResync=${result.needsResync}',
        name: 'SyncOrchestrator',
      );

      // 3. Fire callbacks for ALL domains (skip if stopped — providers may
      //    already be disposed after scope rotation during logout).
      if (result.hasChanges) {
        NotificationSyncService.instance.onSyncComplete?.call();
        ChatSyncService.instance.onSyncComplete?.call();
        FocusSyncService.instance.onSyncComplete?.call();
        developer.log(
          '[DIAG] _runSync: firing FocusRoomSyncService.onSyncComplete '
          '(callback=${FocusRoomSyncService.instance.onSyncComplete != null})',
          name: 'SyncOrchestrator',
        );
        FocusRoomSyncService.instance.onSyncComplete?.call();
      }
      if (result.needsResync) {
        _scheduleResync();
      }

      // 4. Save versions + cursor atomically.
      //    On 304 / mutex / auth-skip: serverVersions is null → nothing to save.
      //    Skip if stopped — DB may already be cleared by logout.
      if (!_started) return; // checkpoint: don't persist if logout cleared DB
      if (serverVersions != null) {
        await SyncVersionStore.instance.saveVersionsAndCursor(
          serverVersions,
          AggregatedSyncService.instance.cursor,
        );
      }

      _backoff.onSuccess();
      if (result.onboardingStateAuthoritative && !_firstSyncSettled) {
        _firstSyncSettled = true;
        onFirstSyncSettled?.call();
      }
    } on SyncRateLimitedException catch (e) {
      _backoff.onFailure();
      _retryAfterDelay = e.retryAfter;
      developer.log(
        'SyncOrchestrator: sync rate limited'
        '${e.retryAfter != null ? ', retry after ${e.retryAfter!.inSeconds}s' : ''}',
        name: 'SyncOrchestrator',
      );
      _scheduleRetry();
    } on SyncServerException catch (e, stackTrace) {
      _backoff.onFailure();
      developer.log(
        'SyncOrchestrator: server sync failure ${e.statusCode}',
        name: 'SyncOrchestrator',
        error: e,
        stackTrace: stackTrace,
      );
      _scheduleRetry();
    } on ApiHttpException catch (e, stackTrace) {
      if (e.statusCode == 429) {
        _backoff.onFailure();
        _retryAfterDelay = e.retryAfter();
        _scheduleRetry();
      } else if (e.statusCode >= 500) {
        _backoff.onFailure();
        _scheduleRetry();
      } else {
        // 4xx client errors (non-429): don't retry, permanent failure
        _backoff.reset();
        _retryAfterDelay = null;
      }
      developer.log(
        'SyncOrchestrator: HTTP sync failure ${e.statusCode}',
        name: 'SyncOrchestrator',
        error: e,
        stackTrace: stackTrace,
      );
    } catch (e, stackTrace) {
      final status = _extractHttpStatus(e);
      if (status == 429 || (status != null && status >= 500)) {
        _backoff.onFailure();
        _scheduleRetry();
      } else if (status != null && status >= 400 && status < 500) {
        _backoff.reset();
        _retryAfterDelay = null;
      } else {
        // Network errors, timeouts, etc. — retry
        _backoff.onFailure();
        _scheduleRetry();
      }
      developer.log(
        'SyncOrchestrator: sync round failed: $e',
        name: 'SyncOrchestrator',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _syncInProgress = false;
    }
  }

  /// Schedule a retry with exponential backoff.
  /// Gives up after 10 consecutive failures to avoid infinite loops.
  /// Uses a cancellable [Timer] so stopAndResetAll() can prevent firing.
  void _scheduleRetry() {
    if (!_started) return;
    if (_backoff.failureCount > 10) return;
    final delay = _retryAfterDelay ?? _backoff.getNextDelay();
    _retryAfterDelay = null;
    final effectiveDelay = delay > Duration.zero
        ? delay
        : const Duration(seconds: 2);
    _retryTimer?.cancel();
    _retryTimer = Timer(effectiveDelay, () => syncNow());
  }

  /// Schedule a resync after page-delay (used when server has more pages).
  /// Uses the same cancellable [_retryTimer].
  void _scheduleResync() {
    if (!_started) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(AggregatedSyncService.minPageDelay, () => syncNow());
  }

  /// Current user ID bound to running sync services.
  String? get userId => _userId;

  /// Current session epoch bound to running sync services.
  int? get sessionEpoch => _sessionEpoch;

  int? _extractHttpStatus(Object error) {
    final text = error.toString();
    final match = RegExp(r'failed:\s*(\d{3})').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
