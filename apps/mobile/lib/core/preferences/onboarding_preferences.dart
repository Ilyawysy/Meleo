import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPreferences {
  static const String _keyPrefix = 'onboarding_completed_';
  static const String _pendingPrefix = 'onboarding_pending_sync_';

  static Future<bool> isCompletedForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_keyPrefix$userId') ?? false;
  }

  static Future<void> markCompletedForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_keyPrefix$userId', true);
  }

  static Future<void> clearForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$userId');
    await prefs.remove('$_pendingPrefix$userId');
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_keyPrefix) || key.startsWith(_pendingPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  static Future<bool> isPendingSyncForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_pendingPrefix$userId') ?? false;
  }

  static Future<void> markPendingSyncForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_pendingPrefix$userId', true);
  }

  static Future<void> clearPendingSyncForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_pendingPrefix$userId');
  }
}
