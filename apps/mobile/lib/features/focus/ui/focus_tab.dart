import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/app_blocker_channel.dart';
import '../data/blocked_apps_db.dart';
import '../data/focus_db.dart';
import '../data/focus_sync_service.dart';
import '../data/checklist_item_db.dart';
import '../models/checklist_item.dart';
import '../models/focus_models.dart';
import '../models/focus_room_data.dart';
import '../models/gamification_models.dart';
import '../models/task.dart';
import '../models/focus_room.dart' as room_model;
import '../providers/active_room_provider.dart';
import '../providers/focus_rooms_provider.dart';
import '../../profile/ui/settings_screen.dart';
import 'widgets/duration_adjustment_sheet.dart';
import 'widgets/focus_completion_dialog.dart';
import 'widgets/focus_room.dart';
import 'widgets/focus_session_view.dart';
import 'help/help_flow_screen.dart';
import 'widgets/add_room_sheet.dart';
import 'mascot_skins_shop_screen.dart';
import 'widgets/switch_task_sheet.dart';

class FocusTab extends ConsumerStatefulWidget {
  final FocusRoomData? initialData;
  final VoidCallback? onRefreshFocus;
  final ValueChanged<bool>? onSessionViewChanged;

  const FocusTab({
    super.key,
    this.initialData,
    this.onRefreshFocus,
    this.onSessionViewChanged,
  });

  @override
  ConsumerState<FocusTab> createState() => FocusTabState();
}

class FocusTabState extends ConsumerState<FocusTab> {
  final _focusDb = FocusDb();
  double _coins = 0.0;
  String? _error;
  GamificationProfile? _profile;

  final _appBlocker = AppBlockerChannel();
  final _blockedAppsDb = BlockedAppsDb();
  final _checklistItemDb = FocusChecklistItemDb();
  List<ChecklistItem> _checklistItems = [];
  bool _blockAppsEnabled = false;

  FocusSession? _session;
  Task? _sessionTask;
  Timer? _ticker;
  DateTime? _runStart;
  int _creditedMinutesToday = 0;
  bool _isStopwatch = false;
  bool _adjustmentSheetOpen = false;
  bool _viewingSession = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _applyRoomData(widget.initialData!);
    } else {
      _loadRoom();
    }
  }

  @override
  void didUpdateWidget(covariant FocusTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialData != null &&
        widget.initialData != oldWidget.initialData) {
      _applyRoomData(widget.initialData!);
    }
  }

  void _applyRoomData(FocusRoomData d) {
    setState(() {
      _coins = d.coins;
      _profile = d.profile;
      _error = d.error;
      _session = d.session;
      _sessionTask = d.sessionTask;
      if (d.session != null) {
        _isStopwatch = d.session!.plannedDurationSec == 0;
      }
      if (d.session != null &&
          d.session!.status == FocusSessionStatus.running) {
        _runStart = d.session!.lastStateChangeAt ?? DateTime.now();
        _startTicker();
      } else {
        _runStart = null;
        _ticker?.cancel();
      }
    });
    _focusDb.getAlreadyCreditedToday().then((v) {
      if (mounted) setState(() => _creditedMinutesToday = v);
    });
    _loadChecklist();
    if (d.session != null && d.session!.status == FocusSessionStatus.running) {
      _focusDb.getCacheValue('session_block_apps_enabled').then((v) {
        if (v == 'true' && mounted) {
          setState(() => _blockAppsEnabled = true);
          _startBlockingIfNeeded();
        }
      });
    }
  }

  void _setViewingSession(bool value) {
    if (_viewingSession == value) return;
    setState(() => _viewingSession = value);
    widget.onSessionViewChanged?.call(value);
  }

  Future<void> _loadChecklist() async {
    if (_session?.taskId == null) {
      setState(() => _checklistItems = []);
      return;
    }
    final items = await _checklistItemDb.list(_session!.taskId!);
    if (mounted) setState(() => _checklistItems = items);
  }

  Future<void> _toggleChecklistItem(ChecklistItem item) async {
    await _checklistItemDb.update(item.id, isDone: !item.isDone);
    setState(() {
      _checklistItems = _checklistItems
          .map((i) => i.id == item.id ? i.copyWith(isDone: !i.isDone) : i)
          .toList();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadRoom() async {
    setState(() => _error = null);
    try {
      final cached = await Future.wait([
        _focusDb.getBalance(),
        _focusDb.getProfile(),
        _focusDb.getActiveSession(),
      ]);
      final cachedBalance = cached[0] as Balance?;
      final cachedProfile = cached[1] as GamificationProfile?;
      final cachedSession = cached[2] as FocusSession?;
      final creditedToday = await _focusDb.getAlreadyCreditedToday();
      if (!mounted) return;

      setState(() {
        _coins = cachedBalance?.coins ?? 0.0;
        _profile = cachedProfile;
        _creditedMinutesToday = creditedToday;
        if (cachedSession != null) {
          _session = cachedSession;
          _isStopwatch = cachedSession.plannedDurationSec == 0;
          if (cachedSession.status == FocusSessionStatus.running) {
            _runStart = cachedSession.lastStateChangeAt ?? DateTime.now();
            _startTicker();
          }
        }
      });

      _loadChecklist();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить кэш: $e');
    }
  }

  Future<void> _refreshProfile() async {
    final profile = await _focusDb.getProfile();
    final creditedToday = await _focusDb.getAlreadyCreditedToday();
    if (!mounted) return;
    if (profile != null) {
      setState(() {
        _profile = profile;
        _coins = profile.coins;
        _creditedMinutesToday = creditedToday;
      });
    }
    widget.onRefreshFocus?.call();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openShop() async {
    final coinsNotifier = ValueNotifier<double>(_coins);
    void onChange() {
      final v = coinsNotifier.value;
      if (v == _coins) return;
      // Persist optimistic balance — sync will reconcile with server truth.
      _focusDb.saveBalance(Balance(coins: v));
      if (mounted) setState(() => _coins = v);
    }

    coinsNotifier.addListener(onChange);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              MascotSkinsShopScreen(coinsNotifier: coinsNotifier),
        ),
      );
    } finally {
      coinsNotifier.removeListener(onChange);
      coinsNotifier.dispose();
    }
  }

  Future<void> startFocusSession({Task? initialTask}) async {
    // "Start Focus" creates a fresh room with the entered settings and
    // immediately enters its active focus view. (initialTask is unused under
    // the new flow — kept for callers that still pass it.)
    final newRoom = await showModalBottomSheet<room_model.FocusRoom?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddRoomSheet(
        profile: _profile,
        autoStart: true,
      ),
    );
    if (newRoom == null) return;

    final durationMin = newRoom.focusDurationMin ?? _profile?.focusDurationMin ?? 25;
    unawaited(ref.read(activeRoomIdProvider.notifier).set(newRoom.id));
    _blockAppsEnabled = false;

    try {
      final session = await _focusDb.createSessionLocally(
        plannedDurationSec: durationMin * 60,
        taskId: null,
        roomId: newRoom.id,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionTask = null;
        _isStopwatch = false;
      });
      _setViewingSession(true);
      _loadChecklist();
    } catch (e) {
      _snack('Не удалось создать сессию: $e');
    }
  }

  Future<void> startFocusSessionForRoom(
      String localRoomId, int durationMinutes) async {
    unawaited(ref.read(activeRoomIdProvider.notifier).set(localRoomId));
    _blockAppsEnabled = false;
    try {
      final session = await _focusDb.createSessionLocally(
        plannedDurationSec: durationMinutes * 60,
        taskId: null,
        roomId: localRoomId,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionTask = null;
        _isStopwatch = false;
      });
      _setViewingSession(true);
      _loadChecklist();
    } catch (e) {
      _snack('Не удалось создать сессию: $e');
    }
  }

  Future<void> _openSegment() async {
    if (_session == null || _session!.taskId == null) return;
    await _focusDb.createSegment(_session!.id, _session!.taskId!);
  }

  Future<void> _closeSegment() async {
    if (_session == null) return;
    await _focusDb.closeActiveSegment(
      _session!.id,
      maxSessionElapsedSec: _effectiveElapsedSec(),
    );
  }

  int _effectiveElapsedSec() {
    if (_session == null) return 0;
    final base = _session!.activeElapsedSec;
    if (_session!.status == FocusSessionStatus.running && _runStart != null) {
      return base + DateTime.now().difference(_runStart!).inSeconds;
    }
    return base;
  }

  int _remainingSec() {
    if (_session == null) return 0;
    final remaining = _session!.plannedDurationSec - _effectiveElapsedSec();
    return remaining < 0 ? 0 : remaining;
  }

  static const int _stopwatchMaxFallbackSec = 3 * 3600;

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _session == null) return;
      if (_session!.status != FocusSessionStatus.running) return;
      if (_adjustmentSheetOpen) return;
      if (!_isStopwatch && _remainingSec() <= 0) {
        await _updateState('finish');
      } else if (_isStopwatch) {
        final maxSec = _session!.plannedDurationSec > 0
            ? _session!.plannedDurationSec
            : _stopwatchMaxFallbackSec;
        if (_effectiveElapsedSec() >= maxSec) {
          await _updateState('finish');
        } else {
          setState(() {});
        }
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _startBlockingIfNeeded() async {
    if (!_blockAppsEnabled) return;
    final packages = await _blockedAppsDb.getBlockedApps();
    if (packages.isEmpty) return;
    final hasOverlay = await _appBlocker.hasOverlayPermission();
    final hasUsage = await _appBlocker.hasUsageStatsPermission();
    if (!hasOverlay || !hasUsage) return;
    await _appBlocker.startBlocking(packages);
  }

  Future<void> _handleFinish() async {
    if (_session == null) return;
    await _closeSegment();
    await _appBlocker.stopBlocking();
    if (!mounted) return;
    final actualElapsedSec = _effectiveElapsedSec();

    int chosenOverrideSec;
    if (_profile?.adjustDurationAfterSession ?? false) {
      _adjustmentSheetOpen = true;
      final result = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DurationAdjustmentSheet(
          actualElapsedSec: actualElapsedSec,
          taskTitle: _sessionTask?.title,
        ),
      );
      _adjustmentSheetOpen = false;
      if (result == null || !mounted || _session == null) return;
      chosenOverrideSec = result;
    } else {
      chosenOverrideSec = actualElapsedSec;
    }
    try {
      final session = await _focusDb.updateSessionState(
        _session!.id,
        'finish',
        elapsedOverrideSec: chosenOverrideSec,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _runStart = null;
        _ticker?.cancel();
      });

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Сохраняем результат...'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      debugPrint(
          '[DIAG] Calling pushSessionForResult for session ${session.id}');
      final nav = Navigator.of(context);
      final serverSession =
          await FocusSyncService.instance.pushSessionForResult(session.id);
      debugPrint(
          '[DIAG] pushSessionForResult returned: ${serverSession != null}');
      if (!mounted) return;

      nav.pop();

      final gotServerResponse = serverSession != null;
      await _showCompletionDialog(serverSession ?? session, gotServerResponse);

      // Refresh rooms aggregates after session finishes
      await ref.read(focusRoomsProvider.notifier).refresh();
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _snack('Ошибка управления сессией: $e');
    }
  }

  Future<void> _updateState(String action) async {
    if (_session == null) return;
    if (action == 'finish') {
      await _handleFinish();
      return;
    }
    try {
      final session = await _focusDb.updateSessionState(_session!.id, action);
      if (!mounted) return;

      setState(() {
        _session = session;
        if (session.status == FocusSessionStatus.running) {
          _runStart = DateTime.now();
          _startTicker();
        } else if (session.status == FocusSessionStatus.paused) {
          _runStart = null;
          _ticker?.cancel();
        } else {
          _runStart = null;
          _ticker?.cancel();
        }
      });

      if (action == 'play') {
        await _openSegment();
        await _startBlockingIfNeeded();
      } else if (action == 'pause') {
        await _closeSegment();
        await _appBlocker.stopBlocking();
      }

      if (action == 'pause') return;

      if (action == 'play') {
        await FocusSyncService.instance.pushDirtyOnly();
      }

      if (action == 'cancel') {
        await _closeSegment();
        await _appBlocker.stopBlocking();
        await FocusSyncService.instance.pushDirtyOnly();
        if (!mounted) return;
        setState(() {
          _session = null;
          _sessionTask = null;
          _checklistItems = [];
          _isStopwatch = false;
        });
        _setViewingSession(false);
        unawaited(ref.read(activeRoomIdProvider.notifier).set(null));
        _loadRoom();
      }
    } catch (e) {
      _snack('Ошибка управления сессией: $e');
    }
  }

  Future<void> _showCompletionDialog(
      FocusSession session, bool gotServerResponse) async {
    await showDialog<void>(
      context: context,
      builder: (context) => FocusCompletionDialog(
        session: session,
        gotServerResponse: gotServerResponse,
      ),
    );
    if (!mounted) return;
    setState(() {
      _session = null;
      _sessionTask = null;
      _checklistItems = [];
      _runStart = null;
      _isStopwatch = false;
    });
    _setViewingSession(false);
    unawaited(ref.read(activeRoomIdProvider.notifier).set(null));
    _refreshProfile();
  }

  Future<void> _updateTask(Task? task) async {
    if (_session == null) return;
    try {
      await _closeSegment();
      final updated = await _focusDb.updateSessionTaskLocally(
        _session!.id,
        task?.id,
      );
      if (!mounted) return;
      setState(() {
        _session = updated;
        _sessionTask = task;
      });
      if (updated.status == FocusSessionStatus.running && task != null) {
        await _focusDb.createSegment(updated.id, task.id);
      }
      _loadChecklist();
    } catch (e) {
      _snack('Не удалось обновить задачу: $e');
    }
  }

  String _fmtSec(int seconds) {
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final activeRoomId = ref.watch(activeRoomIdProvider);

    if (_error != null && !_error!.contains('Нет данных')) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ошибка: $_error'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _loadRoom, child: const Text('Повторить')),
          ],
        ),
      );
    }

    // Resolve active room from provider (needed for selected-room widget).
    room_model.FocusRoom? currentRoom;
    if (activeRoomId != null) {
      final roomsAsync = ref.watch(focusRoomsProvider);
      final rooms = roomsAsync.valueOrNull ?? const <room_model.FocusRoom>[];
      for (final r in rooms) {
        if (r.id == activeRoomId) {
          currentRoom = r;
          break;
        }
      }
    }

    // Focus tab layout (HQB0f):
    //   state 1: session exists + viewing       → FocusSessionView
    //   state 2: session exists + not viewing   → FocusRoom (active-session banner)
    //   state 3: no session + activeRoomId set  → FocusRoom (selected-room widget + help)
    //   state 4: no session + no activeRoomId   → FocusRoom (generic + help)
    return SafeArea(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: (_session != null && _viewingSession)
            ? FocusSessionView(
                key: const ValueKey('session'),
                session: _session!,
                task: _sessionTask,
                remainingLabel: _isStopwatch
                    ? _fmtSec(_effectiveElapsedSec())
                    : _fmtSec(_remainingSec()),
                activeElapsedSec: _effectiveElapsedSec(),
                isStopwatch: _isStopwatch,
                onPlay: () => _updateState('play'),
                onPause: () => _updateState('pause'),
                onCancel: () => _updateState('cancel'),
                onFinish: () => _updateState('finish'),
                onChangeTask: () async {
                  final task = await showModalBottomSheet<Task?>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SwitchTaskSheet(
                      currentTask: _sessionTask,
                      elapsedSec: _effectiveElapsedSec(),
                      roomId: '',
                    ),
                  );
                  if (task != null) {
                    await _updateTask(task);
                  }
                },
                checklistItems: _checklistItems,
                onToggleChecklist: _toggleChecklistItem,
                onBack: () => _setViewingSession(false),
              )
            : FocusRoom(
                key: const ValueKey('focus_room'),
                coins: _coins,
                profile: _profile,
                creditedMinutesToday: _creditedMinutesToday,
                onOpenShop: _openShop,
                onStart: startFocusSession,
                onOpenSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
                onOpenHelp: () async {
                  final result = await Navigator.of(context)
                      .push<Map<String, dynamic>?>(
                    MaterialPageRoute(
                      builder: (_) => const HelpFlowScreen(),
                    ),
                  );
                  if (!mounted) return;
                  if (result != null && result['action'] == 'focus') {
                    final activeId = ref.read(activeRoomIdProvider);
                    if (activeId != null) {
                      await startFocusSessionForRoom(
                          activeId, result['duration'] as int);
                    }
                  }
                },
                activeSessionLabel: _session != null
                    ? (_isStopwatch
                        ? _fmtSec(_effectiveElapsedSec())
                        : _fmtSec(_remainingSec()))
                    : null,
                activeSessionSubLabel: _session != null
                    ? (_isStopwatch ? 'elapsed' : 'remaining')
                    : null,
                onReturnToSession:
                    _session != null ? () => _setViewingSession(true) : null,
                activeRoom: _session == null ? currentRoom : null,
                onStartForRoom: (_session == null && activeRoomId != null)
                    ? () {
                        // TODO: default duration should come from user settings.
                        final durationMin =
                            currentRoom?.focusDurationMin ?? _profile?.focusDurationMin ?? 25;
                        startFocusSessionForRoom(activeRoomId, durationMin);
                      }
                    : null,
              ),
      ),
    );
  }
}
