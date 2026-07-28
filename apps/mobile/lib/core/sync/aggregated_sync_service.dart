import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../api_http_exception.dart';
import '../preferences/onboarding_preferences.dart';
import '../sentry_config.dart';
import '../../features/auth/data/token_manager.dart';
import '../../features/onboarding/data/onboarding_service.dart';
import 'sync_versions_api.dart';
import '../../features/chat/data/chat_db.dart';
import '../../features/chat/models/chat_thread.dart';
import '../../features/chat/models/message.dart';
import '../../features/announcements/data/announcement_cache.dart';
import '../../features/announcements/models/announcement.dart';
import '../../features/focus/data/focus_db.dart';
import '../../features/focus/data/mascot_skins_sync_bus.dart';
import '../../features/focus/models/focus_models.dart';
import '../../features/focus/models/gamification_models.dart';
import '../../features/focus/models/mascot_skin.dart';
import '../../features/notifications/data/notification_db.dart';
import '../../features/notifications/models/notification_mapper.dart';
import '../../features/focus/data/focus_room_sync_service.dart';

typedef SyncDelayFn = Future<void> Function(Duration delay);
typedef SyncIsAuthenticatedFn = Future<bool> Function();
typedef SyncCompleteFn = void Function({required bool hasChanges});
typedef SyncFetchOverride =
    Future<http.Response> Function(String? cursor, String? etag);
typedef SyncProcessOverride =
    Future<int> Function(Map<String, dynamic> changes);
typedef SyncPagePersistFn =
    Future<void> Function(DomainVersions appliedVersions, String? cursor);
typedef OnboardingCompletedFn = void Function();
typedef GetUserIdFn = String? Function();

class SyncRateLimitedException implements Exception {
  SyncRateLimitedException({required this.statusCode, this.retryAfter});

  final int statusCode;
  final Duration? retryAfter;

  @override
  String toString() =>
      'SyncRateLimitedException(statusCode=$statusCode, retryAfter=$retryAfter)';
}

class SyncServerException implements Exception {
  SyncServerException({required this.statusCode});

  final int statusCode;

  @override
  String toString() => 'SyncServerException(statusCode=$statusCode)';
}

class AggregatedSyncResult {
  const AggregatedSyncResult({
    required this.hasChanges,
    required this.needsResync,
    required this.onboardingStateAuthoritative,
    this.serverVersions,
  });

  final bool hasChanges;
  final bool needsResync;
  final bool onboardingStateAuthoritative;

  /// Domain versions from the last /sync 200 response.
  /// null when 304 (nothing changed) or sync didn't run (mutex/auth).
  final DomainVersions? serverVersions;
}

/// Aggregated sync service that fetches delta changes from a single /sync endpoint.
///
/// Features:
/// - Cursor-based delta sync (only fetches changes since last cursor)
/// - ETag support (304 Not Modified when no changes)
/// - Pagination loop with max pages per tick (prevents tight loops)
/// - Mutex with _needsResync flag (no lost syncs)
/// - Minimum delay between pages (server courtesy)
/// - Resync intent returned to orchestrator (drain loop outside service)
class AggregatedSyncService {
  AggregatedSyncService({
    ApiClient? apiClient,
    SyncDelayFn? delayFn,
    SyncIsAuthenticatedFn? isAuthenticatedFn,
    SyncCompleteFn? onSyncComplete,
    SyncFetchOverride? fetchOverride,
    SyncProcessOverride? processOverride,
  }) : _api = apiClient ?? ApiClient(),
       _delayFn = delayFn ?? _defaultDelay,
       _isAuthenticatedFn =
           isAuthenticatedFn ?? (() => TokenManager.isAuthenticated),
       _onSyncComplete = onSyncComplete ?? _defaultOnSyncComplete,
       _fetchOverride = fetchOverride,
       _processOverride = processOverride;

  static final AggregatedSyncService instance = AggregatedSyncService();

  final ApiClient _api;
  final SyncDelayFn _delayFn;
  final SyncIsAuthenticatedFn _isAuthenticatedFn;
  final SyncCompleteFn _onSyncComplete;
  final SyncFetchOverride? _fetchOverride;
  final SyncProcessOverride? _processOverride;

  /// Encoded cursor from last successful sync (persisted by orchestrator).
  String? cursor;

  /// ETag from last response for If-None-Match header.
  String? _etag;

  /// Max pages to fetch in one sync tick (prevents infinite loops).
  static const int maxPagesPerTick = 5;

  /// Minimum delay between page fetches.
  static const Duration minPageDelay = Duration(milliseconds: 500);

  bool _syncInFlight = false;
  bool _needsResync = false;
  bool _hasPendingPages = false;

  /// Callback to persist applied versions + cursor per page (crash-safety).
  SyncPagePersistFn? onPagePersist;

  /// Callback invoked when server confirms onboarding_completed == true.
  OnboardingCompletedFn? onOnboardingCompleted;

  /// Returns the current authenticated user ID (set by orchestrator).
  GetUserIdFn? getUserId;

  /// Latest server versions seen across pages (updated to max on each page).
  DomainVersions _targetVersions = DomainVersions.zero;

  /// Versions where cursor has fully caught up (has_more == false).
  /// Only these are persisted and sent as hints on next cycle.
  DomainVersions _appliedVersions = DomainVersions.zero;

  static Future<void> _defaultDelay(Duration delay) => Future.delayed(delay);
  static void _defaultOnSyncComplete({required bool hasChanges}) {}

  /// Reset cursor and ETag (e.g. on logout or user switch).
  void reset() {
    cursor = null;
    _etag = null;
    _syncInFlight = false;
    _needsResync = false;
    _hasPendingPages = false;
    _targetVersions = DomainVersions.zero;
    _appliedVersions = DomainVersions.zero;
  }

  /// Per-domain versions for the current sync cycle.
  /// When set, passed as tv/nv/mv query params so the server can skip
  /// unchanged domain SELECTs.
  DomainVersions? _localVersions;

  /// Run aggregated sync. If already running, sets _needsResync flag.
  ///
  /// [localVersions] — client's last-known domain versions.
  /// Passed to server as tv/nv/mv so it can skip SELECTs for unchanged domains.
  Future<AggregatedSyncResult> sync({
    bool reportAdaptive = true,
    DomainVersions? localVersions,
  }) async {
    // Mutex: if already syncing, mark for resync
    if (_syncInFlight) {
      _needsResync = true;
      return const AggregatedSyncResult(
        hasChanges: false,
        needsResync: true,
        onboardingStateAuthoritative: false,
      );
    }

    if (!(await _isAuthenticatedFn())) {
      developer.log(
        'Sync skipped: not authenticated',
        name: 'AggregatedSyncService',
      );
      if (reportAdaptive) {
        _onSyncComplete(hasChanges: false);
      }
      return const AggregatedSyncResult(
        hasChanges: false,
        needsResync: false,
        onboardingStateAuthoritative: false,
      );
    }

    _syncInFlight = true;
    _needsResync = false;
    _localVersions = localVersions;

    // Initialize version tracking from persisted applied versions.
    _targetVersions = localVersions ?? DomainVersions.zero;
    _appliedVersions = localVersions ?? DomainVersions.zero;

    bool hasAnyChanges = false;
    bool onboardingStateAuthoritative = false;
    int pagesFetched = 0;

    try {
      // Pagination loop (not recursion)
      while (pagesFetched < maxPagesPerTick) {
        final response = await _fetchSync(
          skipEtag: _hasPendingPages || pagesFetched > 0,
        );

        if (response.statusCode == 304) {
          // No changes - server ETag matched
          developer.log(
            'Sync: 304 Not Modified',
            name: 'AggregatedSyncService',
          );
          _hasPendingPages = false;
          break;
        }

        if (response.statusCode == 429) {
          final retryAfter = ApiHttpException.parseRetryAfter(
            response.headers['retry-after'],
          );
          developer.log(
            'Sync: 429 Rate Limited'
            '${retryAfter != null ? ', retry after ${retryAfter.inSeconds}s' : ''}',
            name: 'AggregatedSyncService',
          );
          throw SyncRateLimitedException(
            statusCode: response.statusCode,
            retryAfter: retryAfter,
          );
        }

        if (response.statusCode >= 500) {
          developer.log(
            'Sync: server error ${response.statusCode}',
            name: 'AggregatedSyncService',
          );
          throw SyncServerException(statusCode: response.statusCode);
        }

        if (response.statusCode != 200) {
          developer.log(
            'Sync: unexpected status ${response.statusCode}',
            name: 'AggregatedSyncService',
          );
          throw ApiHttpException(
            method: 'GET',
            path: '/api/v1/sync',
            statusCode: response.statusCode,
            headers: response.headers,
            body: response.body,
          );
        }

        // Update ETag from response
        final newEtag = response.headers['etag'];
        if (newEtag != null) {
          _etag = newEtag;
        }

        final data = json.decode(response.body) as Map<String, dynamic>;
        final hasMore = data['has_more'] as Map<String, dynamic>;
        final changes = data['changes'] as Map<String, dynamic>;

        // Parse domain versions from response
        final versionsJson = data['versions'] as Map<String, dynamic>?;
        if (versionsJson != null) {
          _targetVersions = _targetVersions.maxWith(
            DomainVersions.fromJson(versionsJson),
          );
        }

        // Process changes for each domain
        final changeCount = _processOverride != null
            ? await _processOverride(changes)
            : await _processChanges(changes);
        if (changeCount > 0) {
          hasAnyChanges = true;
        }

        // Handle onboarding_completed from sync response (top-level field)
        final onboardingCompleted = data['onboarding_completed'] as bool?;
        if (onboardingCompleted != null) {
          onboardingStateAuthoritative = true;
          final userId = getUserId?.call();
          if (userId != null) {
            if (onboardingCompleted) {
              await OnboardingPreferences.markCompletedForUser(userId);
              await OnboardingPreferences.clearPendingSyncForUser(userId);
              onOnboardingCompleted?.call();
            } else {
              final hasPending =
                  await OnboardingPreferences.isPendingSyncForUser(userId);
              if (hasPending) {
                // POST hasn't landed yet — retry and keep local cache
                final success = await OnboardingService.markCompletedOnServer();
                if (success) {
                  await OnboardingPreferences.markCompletedForUser(userId);
                  await OnboardingPreferences.clearPendingSyncForUser(userId);
                  onOnboardingCompleted?.call();
                }
              } else {
                // Guard against race: local may already be true if the POST
                // landed between our sync fetch and here.
                final localDone =
                    await OnboardingPreferences.isCompletedForUser(userId);
                if (localDone) {
                  // Local state is ahead of server — mark pending and retry.
                  await OnboardingPreferences.markPendingSyncForUser(userId);
                  await OnboardingService.markCompletedOnServer();
                } else {
                  // Server is authoritative: user hasn't completed onboarding.
                  await OnboardingPreferences.clearForUser(userId);
                }
              }
            }
          }
        }

        // Update cursor for next page/tick
        cursor = data['cursor'] as String?;

        // Promote applied for domains done draining
        _appliedVersions = _appliedVersions.applyCompleted(
          _targetVersions,
          hasMore,
        );

        // Persist cursor + applied versions per-page (crash-safety)
        if (onPagePersist != null) {
          await onPagePersist!(_appliedVersions, cursor);
        }

        pagesFetched++;

        // Check if any domain has more data
        final anyHasMore = hasMore.values.any((v) => v == true);
        if (!anyHasMore) {
          _hasPendingPages = false;
          break;
        }

        // Minimum delay between pages (prevent tight loop)
        if (pagesFetched < maxPagesPerTick) {
          await _delayFn(minPageDelay);
        }
      }

      // If we hit the page limit, signal orchestrator to run another sync cycle.
      if (pagesFetched >= maxPagesPerTick) {
        _hasPendingPages = true;
        _needsResync = true;
      }
      final needsResync = _needsResync;
      _needsResync = false;

      if (reportAdaptive) {
        _onSyncComplete(hasChanges: hasAnyChanges);
      }
      return AggregatedSyncResult(
        hasChanges: hasAnyChanges,
        needsResync: needsResync,
        onboardingStateAuthoritative: onboardingStateAuthoritative,
        serverVersions: pagesFetched > 0 ? _appliedVersions : null,
      );
    } catch (e, stackTrace) {
      developer.log(
        'AggregatedSyncService: sync failed: $e',
        name: 'AggregatedSyncService',
        error: e,
        stackTrace: stackTrace,
      );
      SentryConfig.addBreadcrumb(
        message: 'Aggregated sync failed',
        category: 'sync.aggregated',
        level: SentryLevel.error,
        data: {'error': e.toString()},
      );

      if (TokenManager.isAuthError(e)) {
        await TokenManager.handleAuthFailure(e);
      }
      if (reportAdaptive) {
        _onSyncComplete(hasChanges: false);
      }
      if (pagesFetched > 0) {
        _hasPendingPages = true;
      }
      rethrow;
    } finally {
      _syncInFlight = false;
      _localVersions = null;
    }
  }

  /// Fetch a single sync page from the server.
  ///
  /// Uses [ApiClient.send] for automatic auth headers and 401 retry
  /// with token refresh (consistent with all other API calls).
  Future<http.Response> _fetchSync({required bool skipEtag}) async {
    if (_fetchOverride != null) {
      return _fetchOverride(cursor, skipEtag ? null : _etag);
    }

    final queryParams = <String, dynamic>{'limit': '200'};
    if (cursor != null) {
      queryParams['cursor'] = cursor!;
    }
    if (_localVersions != null) {
      queryParams['tv'] = '${_localVersions!.tasks}';
      queryParams['nv'] = '${_localVersions!.notifications}';
      queryParams['mv'] = '${_localVersions!.messages}';
      queryParams['fv'] = '${_localVersions!.focus}';
    }

    final url = _api.uri('/api/v1/sync', queryParams);

    // Build extra headers (ETag); auth headers are added by ApiClient.send.
    final extraHeaders = <String, String>{};
    if (!skipEtag && _etag != null) {
      extraHeaders['If-None-Match'] = _etag!;
    }

    return _api.send('GET', url, headers: extraHeaders);
  }

  /// Process changes from each domain and upsert into local DB.
  /// Returns total number of changes processed.
  Future<int> _processChanges(Map<String, dynamic> changes) async {
    int total = 0;

    // Tasks (room-based — delegated to FocusRoomSyncService)
    final tasks = changes['tasks'] as List<dynamic>? ?? [];
    if (tasks.isNotEmpty) {
      try {
        final syncSvc = FocusRoomSyncService.instance;
        final processed = await syncSvc.applyRemoteTasks(
          tasks.map((e) => e as Map<String, dynamic>).toList(),
        );
        total += processed;
      } catch (e) {
        developer.log(
          'Sync: tasks processing failed: $e',
          name: 'AggregatedSyncService',
        );
      }
    }

    // Checklist items — delegated to FocusRoomSyncService
    final checklistItems = changes['checklist_items'] as List<dynamic>? ?? [];
    if (checklistItems.isNotEmpty) {
      try {
        final syncSvc = FocusRoomSyncService.instance;
        final processed = await syncSvc.applyRemoteChecklistItems(
          checklistItems.map((e) => e as Map<String, dynamic>).toList(),
        );
        total += processed;
      } catch (e) {
        developer.log(
          'Sync: checklist_items processing failed: $e',
          name: 'AggregatedSyncService',
        );
      }
    }

    // Focus rooms (v23)
    final focusRooms = changes['focus_rooms'] as List<dynamic>? ?? [];
    developer.log(
      '[DIAG] _processChanges: focus_rooms count=${focusRooms.length} '
      'keys=${changes.keys.toList()}',
      name: 'AggregatedSyncService',
    );
    if (focusRooms.isNotEmpty) {
      try {
        final syncSvc = FocusRoomSyncService.instance;
        final processed = await syncSvc.applyRemoteRooms(
          focusRooms.map((e) => e as Map<String, dynamic>).toList(),
        );
        developer.log(
          '[DIAG] _processChanges: applyRemoteRooms processed=$processed '
          '(of ${focusRooms.length})',
          name: 'AggregatedSyncService',
        );
        total += processed;
      } catch (e, st) {
        developer.log(
          '[DIAG] Sync: focus_rooms processing failed: $e',
          name: 'AggregatedSyncService',
          error: e,
          stackTrace: st,
        );
      }
    }

    // Notifications
    final notifications = changes['notifications'] as List<dynamic>? ?? [];
    if (notifications.isNotEmpty) {
      final notifDb = NotificationDb();
      int processed = 0;
      for (final n in notifications) {
        final map = n as Map<String, dynamic>;
        final isDeleted = map['deleted'] as bool? ?? false;
        if (isDeleted) {
          final remoteId = map['id']?.toString();
          if (remoteId != null && remoteId.isNotEmpty) {
            await notifDb.deleteByRemoteIdHard(remoteId);
            processed++;
          }
          continue;
        }
        final notification = notificationFromApiJson(map);
        await notifDb.upsertFromRemote(notification);
        processed++;
      }
      total += processed;
    }

    // Messages
    final messages = changes['messages'] as List<dynamic>? ?? [];
    if (messages.isNotEmpty) {
      final chatDb = ChatDb();
      int processed = 0;
      for (final m in messages) {
        final map = m as Map<String, dynamic>;
        final remoteThreadId = map['thread_id']?.toString();
        final remoteMessageId = map['id']?.toString();
        if (remoteThreadId == null || remoteThreadId.isEmpty) continue;
        if (remoteMessageId == null || remoteMessageId.isEmpty) continue;

        var thread = await chatDb.findByRemoteId(remoteThreadId);
        if (thread == null) {
          final now = DateTime.now().toUtc();
          await chatDb.upsertThreadFromRemote(
            ChatThread(
              id: remoteThreadId,
              title: 'Chat',
              remoteId: remoteThreadId,
              createdAt: now,
              updatedAt: now,
            ),
          );
          thread = await chatDb.findByRemoteId(remoteThreadId);
          if (thread == null) continue;
        }

        DateTime createdAt;
        try {
          createdAt = DateTime.parse(map['created_at'] as String).toUtc();
        } catch (_) {
          createdAt = DateTime.now().toUtc();
        }

        final role = (map['role'] as String? ?? '').toLowerCase();
        final message = Message(
          id: remoteMessageId,
          remoteId: remoteMessageId,
          threadId: thread.id,
          text: map['content'] as String? ?? '',
          isMe: role == 'user',
          ts: createdAt,
          order: (map['order'] as num?)?.toInt() ?? 0,
        );
        await chatDb.upsertMessageFromRemote(message, thread.id);
        processed++;
      }
      total += processed;
    }

    // Focus snapshot (balance/owned_item_ids/profile) — process FIRST so
    // the UI has profile/balance even if session processing fails below.
    final focusSnapshot = changes['focus_snapshot'] as Map<String, dynamic>?;
    developer.log(
      '[SYNC_DIAG] focus_snapshot=${focusSnapshot != null ? "present" : "null"}',
    );
    if (focusSnapshot != null) {
      final focusDb = FocusDb();
      final balanceMap = focusSnapshot['balance'] as Map<String, dynamic>?;
      if (balanceMap != null) {
        await focusDb.saveBalance(Balance.fromJson(balanceMap));
        developer.log('[SYNC_DIAG] balance saved');
      }
      // Process owned_item_ids
      final ownedIds = focusSnapshot['owned_item_ids'] as List<dynamic>?;
      final ownedSet = <String>{};
      if (ownedIds != null) {
        final idList = ownedIds.map((e) => e.toString()).toList();
        ownedSet.addAll(idList);
        await focusDb.saveOwnedItemIds(idList);
      }
      // Shop catalog from focus_snapshot (no separate HTTP request)
      final shopItemsList = focusSnapshot['shop_items'] as List<dynamic>?;
      if (shopItemsList != null && shopItemsList.isNotEmpty) {
        final items = shopItemsList.map((e) {
          final map = e as Map<String, dynamic>;
          final owned = ownedSet.contains(map['id']?.toString() ?? '');
          return ShopItem.fromJson({...map, 'owned': owned});
        }).toList();
        await focusDb.saveShopItems(items);
      } else if (ownedSet.isNotEmpty) {
        // No catalog in response — update owned flags on cached items
        final cached = await focusDb.getShopItems();
        if (cached != null) {
          final updated = cached
              .map((i) => i.copyWith(owned: ownedSet.contains(i.id)))
              .toList();
          await focusDb.saveShopItems(updated);
        }
      }
      // Process active_items
      final activeItemsMap =
          focusSnapshot['active_items'] as Map<String, dynamic>?;
      if (activeItemsMap != null) {
        await focusDb.saveActiveItems(ActiveItems.fromJson(activeItemsMap));
      }
      final profileMap = focusSnapshot['profile'] as Map<String, dynamic>?;
      developer.log(
        '[SYNC_DIAG] profileMap=${profileMap != null ? "present (keys=${profileMap.keys.join(",")})" : "null"}',
      );
      if (profileMap != null) {
        final profile = GamificationProfile.fromJson(profileMap);
        developer.log(
          '[SYNC_DIAG] profile parsed: level=${profile.level}, minimalMode=${profile.minimalMode}',
        );
        await focusDb.saveProfile(profile);
        developer.log('[SYNC_DIAG] profile saved to focus_cache');
      }
      final subscriptionMap =
          focusSnapshot['subscription'] as Map<String, dynamic>?;
      if (subscriptionMap != null) {
        await focusDb.saveSubscription(subscriptionMap);
      }
      final dailyStatsList = focusSnapshot['daily_stats'] as List<dynamic>?;
      if (dailyStatsList != null && dailyStatsList.isNotEmpty) {
        final stats = dailyStatsList
            .map((e) => DailyStat.fromJson(e as Map<String, dynamic>))
            .toList();
        await focusDb.saveDailyStats(stats);
      }

      // Mascot skins: catalog + ownership + active selection
      final mascotSkinsList = focusSnapshot['mascot_skins'] as List<dynamic>?;
      if (mascotSkinsList != null) {
        final ownedSkinIds =
            (focusSnapshot['owned_mascot_skin_ids'] as List<dynamic>? ??
                    const [])
                .map((e) => (e as num).toInt())
                .toSet();
        final activeSkinId = (focusSnapshot['active_mascot_skin_id'] as num?)
            ?.toInt();
        final skins = mascotSkinsList.map((e) {
          final m = e as Map<String, dynamic>;
          final id = m['id'] as int;
          return MascotSkin.fromJson({
            ...m,
            'owned': ownedSkinIds.contains(id),
            'active': id == activeSkinId,
          });
        }).toList();
        MascotSkinsSyncBus.push(
          MascotSkinsCatalog(skins: skins, activeSkinId: activeSkinId),
        );
      }

      total++;
    }

    // Focus sessions (batch transaction)
    final focusSessions = changes['focus_sessions'] as List<dynamic>? ?? [];
    if (focusSessions.isNotEmpty) {
      try {
        final focusDb = FocusDb();
        final sessions = focusSessions
            .map((s) => FocusSession.fromJson(s as Map<String, dynamic>))
            .toList();
        final processed = await focusDb.upsertFromRemoteBatch(sessions);
        total += processed;
      } catch (e) {
        developer.log(
          'Sync: focus_sessions processing failed: $e',
          name: 'AggregatedSyncService',
        );
      }
    }

    // Focus task segments (full snapshot — replace all)
    final focusTaskSegments =
        changes['focus_task_segments'] as List<dynamic>? ?? [];
    if (focusTaskSegments.isNotEmpty) {
      try {
        final focusDb = FocusDb();
        final segments = focusTaskSegments
            .map((s) => FocusTaskSegment.fromJson(s as Map<String, dynamic>))
            .toList();
        await focusDb.replaceAllSegmentsFromRemote(segments);
        total += segments.length;
      } catch (e) {
        developer.log(
          'Sync: focus_task_segments processing failed: $e',
          name: 'AggregatedSyncService',
        );
      }
    }

    if (total > 0) {
      developer.log(
        'Sync: processed $total changes '
        '(tasks=${tasks.length}, checklist=${checklistItems.length}, '
        'notif=${notifications.length}, msg=${messages.length}, '
        'focus=${focusSessions.length}, segments=${focusTaskSegments.length})',
        name: 'AggregatedSyncService',
      );
    }

    // Announcements from sync response
    final announcements = changes['announcements'] as List<dynamic>? ?? [];
    if (announcements.isNotEmpty) {
      final parsed = announcements
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList();
      AnnouncementCache.instance.replaceAll(parsed);
    }

    return total;
  }
}
