import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/focus_db.dart';
import '../data/focus_room_api.dart';
import '../data/focus_room_db.dart';

class ActiveRoomNotifier extends Notifier<String?> {
  static const _kvKey = 'active_focus_room_id';
  static const _kvPendingKey = 'active_focus_room_remote_id_pending';
  static const _kvLocalPendingKey = 'active_focus_room_local_id_pending';

  final _focusDb = FocusDb();
  final _roomDb = FocusRoomDb();
  final _api = FocusRoomApi();
  final Future<String?> Function(String key)? _readCacheOverride;
  final Future<void> Function(String key, String value)? _saveCacheOverride;
  final Future<String?> Function(String localId)? _getRemoteIdOverride;
  final Future<void> Function(String? remoteId)? _setActiveRoomOverride;
  final Future<String?> Function(String remoteId)? _resolveRemoteIdOverride;
  late String _cacheSuffix;
  int _generation = 0;
  int _selectionRevision = 0;
  int? _pendingSelectionRevision;
  Future<void> _operationQueue = Future<void>.value();

  ActiveRoomNotifier({
    Future<String?> Function(String key)? readCache,
    Future<void> Function(String key, String value)? saveCache,
    Future<String?> Function(String localId)? getRemoteId,
    Future<void> Function(String? remoteId)? setActiveRoom,
    Future<String?> Function(String remoteId)? resolveRemoteId,
  }) : _readCacheOverride = readCache,
       _saveCacheOverride = saveCache,
       _getRemoteIdOverride = getRemoteId,
       _setActiveRoomOverride = setActiveRoom,
       _resolveRemoteIdOverride = resolveRemoteId;

  @override
  String? build() {
    ref.watch(domainScopeToken);
    _cacheSuffix =
        ref.watch(sessionScopeProvider.select((state) => state.userId)) ??
        'anonymous';
    _pendingSelectionRevision = null;
    final generation = ++_generation;
    ref.onDispose(() {
      if (_generation == generation) _generation++;
    });
    _hydrate(_context());
    return null;
  }

  Future<void> _hydrate(_ActiveRoomContext context) async {
    final cacheKey = _key(_kvKey, context);
    final localId = await _readCache(cacheKey);
    if (!_isCurrent(context)) return;
    if (localId != null && localId.isNotEmpty) {
      state = localId;
    }
  }

  Future<void> set(String? localRoomId) {
    final context = _context();
    final revision = ++_selectionRevision;
    _pendingSelectionRevision = revision;
    final previous = _operationQueue;
    final operation = _runQueuedSet(localRoomId, context, revision, previous);
    _operationQueue = operation;
    return operation;
  }

  Future<void> _runQueuedSet(
    String? localRoomId,
    _ActiveRoomContext context,
    int revision,
    Future<void> previous,
  ) async {
    try {
      await previous;
    } catch (_) {}
    if (!_isCurrentSelection(context, revision)) return;
    await _set(localRoomId, context, revision);
  }

  Future<void> _set(
    String? localRoomId,
    _ActiveRoomContext context,
    int revision,
  ) async {
    if (!_isCurrentSelection(context, revision)) return;
    state = localRoomId;
    if (!_isCurrentSelection(context, revision)) return;
    await _saveCache(_key(_kvPendingKey, context), '');
    if (!_isCurrentSelection(context, revision)) return;
    if (localRoomId == null) {
      if (!_isCurrentSelection(context, revision)) return;
      await _saveCache(_key(_kvKey, context), '');
      if (!_isCurrentSelection(context, revision)) return;
      await _saveCache(_key(_kvLocalPendingKey, context), '');
      if (!_isCurrentSelection(context, revision)) return;
      try {
        if (!_isCurrentSelection(context, revision)) return;
        await _setActiveRoom(null);
        if (!_isCurrentSelection(context, revision)) return;
        _pendingSelectionRevision = null;
      } catch (e) {
        if (_isCurrentSelection(context, revision) &&
            _pendingSelectionRevision == revision) {
          _pendingSelectionRevision = null;
        }
        developer.log(
          '[ActiveRoom] setActiveRoom(null) failed: $e',
          name: 'ActiveRoomNotifier',
        );
      }
    } else {
      if (!_isCurrentSelection(context, revision)) return;
      await _saveCache(_key(_kvKey, context), localRoomId);
      if (!_isCurrentSelection(context, revision)) return;
      final remoteId = await _getRemoteId(localRoomId);
      if (!_isCurrentSelection(context, revision)) return;
      if (remoteId == null || remoteId.isEmpty) {
        if (!_isCurrentSelection(context, revision)) return;
        await _saveCache(_key(_kvLocalPendingKey, context), localRoomId);
        if (!_isCurrentSelection(context, revision)) return;
        developer.log(
          '[ActiveRoom] room $localRoomId has no remote_id yet, deferring server push',
          name: 'ActiveRoomNotifier',
        );
        return;
      }
      if (!_isCurrentSelection(context, revision)) return;
      await _saveCache(_key(_kvLocalPendingKey, context), localRoomId);
      if (!_isCurrentSelection(context, revision)) return;
      try {
        if (!_isCurrentSelection(context, revision)) return;
        await _setActiveRoom(remoteId);
        if (!_isCurrentSelection(context, revision)) return;
        await _saveCache(_key(_kvLocalPendingKey, context), '');
        if (!_isCurrentSelection(context, revision)) return;
        _pendingSelectionRevision = null;
      } catch (e) {
        developer.log(
          '[ActiveRoom] setActiveRoom failed: $e',
          name: 'ActiveRoomNotifier',
        );
      }
    }
  }

  Future<void> applyFromSync(String? remoteRoomId) {
    final context = _context();
    final revision = _selectionRevision;
    final selectionPending = _pendingSelectionRevision != null;
    final previous = _operationQueue;
    final operation = _runQueuedApplyFromSync(
      remoteRoomId,
      context,
      revision,
      selectionPending,
      previous,
    );
    _operationQueue = operation;
    return operation;
  }

  Future<void> _runQueuedApplyFromSync(
    String? remoteRoomId,
    _ActiveRoomContext context,
    int revision,
    bool selectionPending,
    Future<void> previous,
  ) async {
    try {
      await previous;
    } catch (_) {}
    if (selectionPending || !_isCurrentRevision(context, revision)) return;
    final localPending = await _readCache(_key(_kvLocalPendingKey, context));
    if (!_isCurrentRevision(context, revision)) return;
    if (localPending != null && localPending.isNotEmpty) return;
    if (remoteRoomId == null || remoteRoomId.isEmpty) {
      await _clearLocally(context);
      return;
    }
    final localId = await _resolveRemoteToLocal(remoteRoomId);
    if (!_isCurrentRevision(context, revision)) return;
    if (localId != null) {
      state = localId;
      await _saveCache(_key(_kvKey, context), localId);
      if (!_isCurrentRevision(context, revision)) return;
      await _saveCache(_key(_kvPendingKey, context), '');
    } else {
      await _saveCache(_key(_kvPendingKey, context), remoteRoomId);
      developer.log(
        '[ActiveRoom] remote room $remoteRoomId not in local DB yet, stored as pending',
        name: 'ActiveRoomNotifier',
      );
    }
  }

  Future<void> tryResolvePending() async {
    final context = _context();
    final revision = _selectionRevision;
    final previous = _operationQueue;
    final operation = _runQueuedTryResolve(context, revision, previous);
    _operationQueue = operation;
    return operation;
  }

  Future<void> _runQueuedTryResolve(
    _ActiveRoomContext context,
    int revision,
    Future<void> previous,
  ) async {
    try {
      await previous;
    } catch (_) {}
    if (!_isCurrentRevision(context, revision)) return;
    final localPending = await _readCache(_key(_kvLocalPendingKey, context));
    if (!_isCurrentRevision(context, revision)) return;
    if (localPending != null && localPending.isNotEmpty) {
      final remoteId = await _getRemoteId(localPending);
      if (!_isCurrentRevision(context, revision)) return;
      if (remoteId != null && remoteId.isNotEmpty) {
        try {
          await _setActiveRoom(remoteId);
          if (!_isCurrentRevision(context, revision)) return;
          final currentPending = await _readCache(
            _key(_kvLocalPendingKey, context),
          );
          if (!_isCurrentRevision(context, revision) ||
              currentPending != localPending) {
            return;
          }
          await _saveCache(_key(_kvLocalPendingKey, context), '');
          if (!_isCurrentRevision(context, revision)) return;
          if (_pendingSelectionRevision == revision) {
            _pendingSelectionRevision = null;
          }
        } catch (e) {
          developer.log(
            '[ActiveRoom] deferred setActiveRoom failed: $e',
            name: 'ActiveRoomNotifier',
          );
        }
      }
      return;
    }

    final pending = await _readCache(_key(_kvPendingKey, context));
    if (!_isCurrentRevision(context, revision)) return;
    if (pending == null || pending.isEmpty) return;
    final localId = await _resolveRemoteToLocal(pending);
    if (!_isCurrentRevision(context, revision)) return;
    if (localId != null) {
      state = localId;
      await _saveCache(_key(_kvKey, context), localId);
      if (!_isCurrentRevision(context, revision)) return;
      final currentPending = await _readCache(_key(_kvPendingKey, context));
      if (!_isCurrentRevision(context, revision) || currentPending != pending) {
        return;
      }
      await _saveCache(_key(_kvPendingKey, context), '');
      developer.log(
        '[ActiveRoom] resolved pending $pending → local $localId',
        name: 'ActiveRoomNotifier',
      );
    }
  }

  Future<void> clearLocally() => _clearLocally(_context());

  Future<void> _clearLocally(_ActiveRoomContext context) async {
    if (!_isCurrent(context)) return;
    state = null;
    await _saveCache(_key(_kvKey, context), '');
    if (!_isCurrent(context)) return;
    await _saveCache(_key(_kvPendingKey, context), '');
    if (!_isCurrent(context)) return;
    await _saveCache(_key(_kvLocalPendingKey, context), '');
  }

  _ActiveRoomContext _context() =>
      _ActiveRoomContext(_generation, _cacheSuffix);

  bool _isCurrent(_ActiveRoomContext context) =>
      context.generation == _generation && context.suffix == _cacheSuffix;

  bool _isCurrentSelection(_ActiveRoomContext context, int revision) =>
      _isCurrent(context) && revision == _selectionRevision;

  bool _isCurrentRevision(_ActiveRoomContext context, int revision) =>
      _isCurrent(context) && revision == _selectionRevision;

  String _key(String base, _ActiveRoomContext context) =>
      '${base}_${context.suffix}';

  Future<String?> _getRemoteId(String localId) async {
    if (_getRemoteIdOverride != null) {
      return _getRemoteIdOverride(localId);
    }
    final room = await _roomDb.getById(localId);
    return room?.remoteId;
  }

  Future<String?> _readCache(String key) =>
      _readCacheOverride?.call(key) ?? _focusDb.getCacheValue(key);

  Future<void> _saveCache(String key, String value) =>
      _saveCacheOverride?.call(key, value) ??
      _focusDb.saveCacheValue(key, value);

  Future<void> _setActiveRoom(String? remoteId) =>
      _setActiveRoomOverride?.call(remoteId) ?? _api.setActiveRoom(remoteId);

  Future<String?> _resolveRemoteToLocal(String remoteId) async {
    if (_resolveRemoteIdOverride != null) {
      return _resolveRemoteIdOverride(remoteId);
    }
    final rooms = await _roomDb.listForUser();
    for (final r in rooms) {
      if (r.remoteId == remoteId) return r.id;
    }
    final archived = await _roomDb.listForUser(archived: true);
    for (final r in archived) {
      if (r.remoteId == remoteId) return r.id;
    }
    return null;
  }
}

class _ActiveRoomContext {
  const _ActiveRoomContext(this.generation, this.suffix);

  final int generation;
  final String suffix;
}

final activeRoomIdProvider = NotifierProvider<ActiveRoomNotifier, String?>(
  ActiveRoomNotifier.new,
  dependencies: [domainScopeToken, sessionScopeProvider],
);
