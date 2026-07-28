import 'dart:convert';
import 'focus_db.dart';

class BlockedAppsDb {
  static const _key = 'blocked_app_packages';
  final _focusDb = FocusDb();

  Future<List<String>> getBlockedApps() async {
    final raw = await _focusDb.getCacheValue(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<String>();
  }

  Future<void> saveBlockedApps(List<String> packageNames) async {
    await _focusDb.saveCacheValue(_key, jsonEncode(packageNames));
  }
}
