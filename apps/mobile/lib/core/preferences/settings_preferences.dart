import 'package:shared_preferences/shared_preferences.dart';

class SettingsPreferences {
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keyNotificationsSound = 'notifications_sound';
  static const String _keyNotificationsVibration = 'notifications_vibration';
  static const String _keyQuietHoursEnabled = 'quiet_hours_enabled';
  static const String _keyQuietHoursStart = 'quiet_hours_start';
  static const String _keyQuietHoursEnd = 'quiet_hours_end';
  static const String _keyDailyReminderEnabled = 'daily_reminder_enabled';
  static const String _keyDailyReminderTime = 'daily_reminder_time';
  static const String _keyShowXpAnimations = 'show_xp_animations';
  static const String _keyXpSoundEnabled = 'xp_sound_enabled';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyCompletionSound = 'completion_sound';
  static const String _keyAmbientSound = 'ambient_sound';
  static const String _keyVibrateOnCompletion = 'vibrate_on_completion';

  static Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationsEnabled) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationsEnabled, value);
  }

  static Future<bool> getNotificationsSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationsSound) ?? true;
  }

  static Future<void> setNotificationsSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationsSound, value);
  }

  static Future<bool> getNotificationsVibration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationsVibration) ?? true;
  }

  static Future<void> setNotificationsVibration(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationsVibration, value);
  }

  static Future<bool> getQuietHoursEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyQuietHoursEnabled) ?? false;
  }

  static Future<void> setQuietHoursEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyQuietHoursEnabled, value);
  }

  static Future<String> getQuietHoursStart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyQuietHoursStart) ?? '23:00';
  }

  static Future<void> setQuietHoursStart(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyQuietHoursStart, value);
  }

  static Future<String> getQuietHoursEnd() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyQuietHoursEnd) ?? '07:00';
  }

  static Future<void> setQuietHoursEnd(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyQuietHoursEnd, value);
  }

  static Future<bool> getDailyReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDailyReminderEnabled) ?? false;
  }

  static Future<void> setDailyReminderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailyReminderEnabled, value);
  }

  static Future<String> getDailyReminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDailyReminderTime) ?? '20:00';
  }

  static Future<void> setDailyReminderTime(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDailyReminderTime, value);
  }

  static Future<bool> getShowXpAnimations() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowXpAnimations) ?? true;
  }

  static Future<void> setShowXpAnimations(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowXpAnimations, value);
  }

  static Future<bool> getXpSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyXpSoundEnabled) ?? true;
  }

  static Future<void> setXpSoundEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyXpSoundEnabled, value);
  }

  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? 'system';
  }

  static Future<void> setThemeMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, value);
  }

  static Future<String> getCompletionSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCompletionSound) ?? 'chime';
  }

  static Future<void> setCompletionSound(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCompletionSound, value);
  }

  static Future<String> getAmbientSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAmbientSound) ?? 'none';
  }

  static Future<void> setAmbientSound(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAmbientSound, value);
  }

  static Future<bool> getVibrateOnCompletion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVibrateOnCompletion) ?? true;
  }

  static Future<void> setVibrateOnCompletion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVibrateOnCompletion, value);
  }

  /// Clears notification-related preferences only.
  /// Keeps xp_animations and xp_sound since they are device prefs.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyNotificationsEnabled);
    await prefs.remove(_keyNotificationsSound);
    await prefs.remove(_keyNotificationsVibration);
    await prefs.remove(_keyQuietHoursEnabled);
    await prefs.remove(_keyQuietHoursStart);
    await prefs.remove(_keyQuietHoursEnd);
    await prefs.remove(_keyDailyReminderEnabled);
    await prefs.remove(_keyDailyReminderTime);
  }
}
