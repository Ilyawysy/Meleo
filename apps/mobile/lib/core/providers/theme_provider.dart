import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/settings_preferences.dart';
import '../../features/focus/data/focus_db.dart';
import '../../features/focus/data/focus_sync_service.dart';

class ThemeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    // Try server-synced profile first, fall back to local SharedPreferences
    final profile = await FocusDb().getProfile();
    if (profile?.themeMode != null) {
      return _fromString(profile!.themeMode);
    }
    final local = await SettingsPreferences.getThemeMode();
    return _fromString(local);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = AsyncValue.data(mode);
    final modeStr = _toString(mode);
    // Save to SharedPreferences (survives logout, device-level)
    await SettingsPreferences.setThemeMode(modeStr);
    // Save to server via FocusDb + sync
    await FocusDb().setPendingProfileSettings(themeMode: modeStr);
    await FocusSyncService.instance.pushDirtyOnly();
  }

  static ThemeMode _fromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themeProvider =
    AsyncNotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
