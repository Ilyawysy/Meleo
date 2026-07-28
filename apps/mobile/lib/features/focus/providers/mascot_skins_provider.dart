import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/mascot_skins_api.dart';
import '../data/mascot_skins_sync_bus.dart';
import '../models/mascot_skin.dart';

const String _prefsKeyPrefix = 'mascot_skins_catalog_v1_';

class MascotSkinsState {
  final MascotSkinsCatalog? catalog;
  final String? error;

  const MascotSkinsState({this.catalog, this.error});

  MascotSkinsState copyWith({
    MascotSkinsCatalog? catalog,
    String? error,
    bool clearError = false,
  }) => MascotSkinsState(
    catalog: catalog ?? this.catalog,
    error: clearError ? null : (error ?? this.error),
  );
}

/// State holder for mascot skins.
///
/// Reads come from aggregated sync (via [MascotSkinsSyncBus]). Writes
/// (buy / set-active) are direct REST calls with optimistic UI: local state
/// updates immediately, the API call happens in the background. The next
/// aggregated sync will reconcile the truth (server bumps focus_version on
/// purchase or active-skin change, so the snapshot is delivered).
///
/// Cached to [SharedPreferences] for offline-first cold starts.
class MascotSkinsNotifier extends StateNotifier<MascotSkinsState> {
  final MascotSkinsApi _api;
  final String? _userId;
  final Future<String?> Function(String key)? _readCacheOverride;
  final Future<void> Function(String key, String value)? _writeCacheOverride;
  late final StreamSubscription<MascotSkinsCatalog> _busSub;
  bool _disposed = false;
  int _busRevision = 0;

  MascotSkinsNotifier({
    required String? userId,
    MascotSkinsApi? api,
    Future<String?> Function(String key)? readCache,
    Future<void> Function(String key, String value)? writeCache,
  }) : _api = api ?? MascotSkinsApi(),
       _userId = userId,
       _readCacheOverride = readCache,
       _writeCacheOverride = writeCache,
       super(const MascotSkinsState()) {
    _busSub = MascotSkinsSyncBus.stream.listen((catalog) async {
      if (_disposed) return;
      _busRevision++;
      state = state.copyWith(catalog: catalog, clearError: true);
      await _persist(catalog);
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Load cached catalog (offline-first).
    try {
      final prefsKey = _prefsKey;
      if (prefsKey == null) return;
      final busRevision = _busRevision;
      final raw = await _readCache(prefsKey);
      if (_disposed || busRevision != _busRevision) return;
      if (raw != null) {
        final cached = MascotSkinsCatalog.fromJson(
          json.decode(raw) as Map<String, dynamic>,
        );
        if (_disposed || busRevision != _busRevision) return;
        state = state.copyWith(catalog: cached);
      }
    } catch (_) {
      // Ignore — sync will populate.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _busSub.cancel();
    super.dispose();
  }

  Future<void> _persist(MascotSkinsCatalog c) async {
    try {
      if (_disposed) return;
      final prefsKey = _prefsKey;
      if (prefsKey == null) return;
      await _writeCache(prefsKey, json.encode(c.toJson()));
    } catch (_) {
      // Best-effort cache.
    }
  }

  String? get _prefsKey =>
      _userId == null || _userId.isEmpty ? null : '$_prefsKeyPrefix$_userId';

  Future<String?> _readCache(String key) async {
    if (_readCacheOverride != null) return _readCacheOverride(key);
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _writeCache(String key, String value) async {
    if (_writeCacheOverride != null) {
      await _writeCacheOverride(key, value);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  /// Optimistically mark skin as owned, then call API. Rolls back on error.
  Future<void> buy(int skinId) async {
    if (_disposed) return;
    final cat = state.catalog;
    if (cat == null) return;
    final original = cat;

    final updated = MascotSkinsCatalog(
      skins: cat.skins
          .map((s) => s.id == skinId ? s.copyWith(owned: true) : s)
          .toList(),
      activeSkinId: cat.activeSkinId,
    );
    state = state.copyWith(catalog: updated);
    await _persist(updated);
    if (_disposed) return;

    try {
      if (_disposed) return;
      await _api.buy(skinId);
      // Server bumps focus_version → next sync delivers reconciled state.
    } catch (e) {
      if (_disposed) rethrow;
      state = state.copyWith(catalog: original, error: e.toString());
      await _persist(original);
      rethrow;
    }
  }

  /// Optimistically toggle the active skin, then call API. Rolls back on error.
  Future<void> setActive(int? skinId) async {
    if (_disposed) return;
    final cat = state.catalog;
    if (cat == null) return;
    final original = cat;

    final updated = MascotSkinsCatalog(
      skins: cat.skins.map((s) => s.copyWith(active: s.id == skinId)).toList(),
      activeSkinId: skinId,
    );
    state = state.copyWith(catalog: updated);
    await _persist(updated);
    if (_disposed) return;

    try {
      if (_disposed) return;
      await _api.setActive(skinId);
      if (_disposed) return;
    } catch (e) {
      if (_disposed) rethrow;
      state = state.copyWith(catalog: original, error: e.toString());
      await _persist(original);
      rethrow;
    }
  }
}

final mascotSkinsProvider =
    StateNotifierProvider<MascotSkinsNotifier, MascotSkinsState>((ref) {
      ref.watch(domainScopeToken);
      final userId = ref.watch(
        sessionScopeProvider.select((state) => state.userId),
      );
      return MascotSkinsNotifier(userId: userId);
    }, dependencies: [domainScopeToken, sessionScopeProvider]);

/// The currently active skin (or `null` if none — defaults active).
final activeMascotSkinProvider = Provider<MascotSkin?>((ref) {
  final cat = ref.watch(mascotSkinsProvider).catalog;
  return cat?.activeSkin;
}, dependencies: [mascotSkinsProvider]);
