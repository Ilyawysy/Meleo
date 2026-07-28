import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/preferences/settings_preferences.dart';
import '../../notifications/services/local_notification_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _notificationsEnabled = true;
  bool _notificationsSound = true;
  bool _notificationsVibration = true;
  bool _quietHoursEnabled = false;
  String _quietHoursStart = '23:00';
  String _quietHoursEnd = '07:00';
  bool _dailyReminderEnabled = false;
  String _dailyReminderTime = '20:00';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ne = await SettingsPreferences.getNotificationsEnabled();
    final ns = await SettingsPreferences.getNotificationsSound();
    final nv = await SettingsPreferences.getNotificationsVibration();
    final qe = await SettingsPreferences.getQuietHoursEnabled();
    final qs = await SettingsPreferences.getQuietHoursStart();
    final qend = await SettingsPreferences.getQuietHoursEnd();
    final de = await SettingsPreferences.getDailyReminderEnabled();
    final dt = await SettingsPreferences.getDailyReminderTime();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = ne;
      _notificationsSound = ns;
      _notificationsVibration = nv;
      _quietHoursEnabled = qe;
      _quietHoursStart = qs;
      _quietHoursEnd = qend;
      _dailyReminderEnabled = de;
      _dailyReminderTime = dt;
      _loaded = true;
    });
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(String current, void Function(String) onPicked) async {
    final picked = await showTimePicker(context: context, initialTime: _parseTime(current));
    if (picked != null) onPicked(_fmt(picked));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            // Nav
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _backButton(),
                  Text('Notifications', style: AppTypography.heading18()),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Main toggle
            _card([
              _toggleRow(
                title: 'Push Notifications',
                subtitle: 'Enable all notifications',
                value: _notificationsEnabled,
                onChanged: (v) async {
                  setState(() => _notificationsEnabled = v);
                  await SettingsPreferences.setNotificationsEnabled(v);
                  final svc = LocalNotificationService();
                  if (v) {
                    await svc.rescheduleAllNotifications();
                    if (_dailyReminderEnabled) {
                      await svc.scheduleDailyReminder(_parseTime(_dailyReminderTime));
                    }
                  } else {
                    await svc.cancelAllNotifications();
                    await svc.cancelDailyReminder();
                  }
                },
              ),
            ]),
            const SizedBox(height: 14),

            // Sound & vibration
            _sectionLabel('ALERTS'),
            const SizedBox(height: 8),
            _card([
              _toggleRow(
                title: 'Sound',
                subtitle: 'Play sound for notifications',
                value: _notificationsSound,
                enabled: _notificationsEnabled,
                onChanged: (v) async {
                  setState(() => _notificationsSound = v);
                  await SettingsPreferences.setNotificationsSound(v);
                },
              ),
              _div(),
              _toggleRow(
                title: 'Vibration',
                subtitle: 'Vibrate for notifications',
                value: _notificationsVibration,
                enabled: _notificationsEnabled,
                onChanged: (v) async {
                  setState(() => _notificationsVibration = v);
                  await SettingsPreferences.setNotificationsVibration(v);
                },
              ),
            ]),
            const SizedBox(height: 14),

            // Quiet hours
            _sectionLabel('QUIET HOURS'),
            const SizedBox(height: 8),
            _card([
              _toggleRow(
                title: 'Quiet Hours',
                subtitle: 'Mute notifications during set hours',
                value: _quietHoursEnabled,
                enabled: _notificationsEnabled,
                onChanged: (v) async {
                  setState(() => _quietHoursEnabled = v);
                  await SettingsPreferences.setQuietHoursEnabled(v);
                  await LocalNotificationService().rescheduleAllNotifications();
                },
              ),
              if (_quietHoursEnabled && _notificationsEnabled) ...[
                _div(),
                _timeRow('Start', _quietHoursStart, () {
                  _pickTime(_quietHoursStart, (t) async {
                    setState(() => _quietHoursStart = t);
                    await SettingsPreferences.setQuietHoursStart(t);
                    await LocalNotificationService().rescheduleAllNotifications();
                  });
                }),
                _div(),
                _timeRow('End', _quietHoursEnd, () {
                  _pickTime(_quietHoursEnd, (t) async {
                    setState(() => _quietHoursEnd = t);
                    await SettingsPreferences.setQuietHoursEnd(t);
                    await LocalNotificationService().rescheduleAllNotifications();
                  });
                }),
              ],
            ]),
            const SizedBox(height: 14),

            // Daily reminder
            _sectionLabel('DAILY REMINDER'),
            const SizedBox(height: 8),
            _card([
              _toggleRow(
                title: 'Daily Reminder',
                subtitle: 'Remind you about tasks each day',
                value: _dailyReminderEnabled,
                enabled: _notificationsEnabled,
                onChanged: (v) async {
                  setState(() => _dailyReminderEnabled = v);
                  await SettingsPreferences.setDailyReminderEnabled(v);
                  final svc = LocalNotificationService();
                  if (v) {
                    await svc.scheduleDailyReminder(_parseTime(_dailyReminderTime));
                  } else {
                    await svc.cancelDailyReminder();
                  }
                },
              ),
              if (_dailyReminderEnabled && _notificationsEnabled) ...[
                _div(),
                _timeRow('Reminder time', _dailyReminderTime, () {
                  _pickTime(_dailyReminderTime, (t) async {
                    setState(() => _dailyReminderTime = t);
                    await SettingsPreferences.setDailyReminderTime(t);
                    if (_dailyReminderEnabled) {
                      await LocalNotificationService().scheduleDailyReminder(_parseTime(t));
                    }
                  });
                }),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  // ── Building blocks ──

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.caption12(color: AppColors.textLight).copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }

  Widget _div() => Container(height: 1, color: AppColors.divider);

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final effectiveValue = enabled ? value : false;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.body15(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.caption12(color: AppColors.textLight)),
                ],
              ),
            ),
            _customSwitch(effectiveValue, enabled ? onChanged : (_) {}),
          ],
        ),
      ),
    );
  }

  Widget _timeRow(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTypography.body15(fontWeight: FontWeight.w500)),
            ),
            Text(value, style: AppTypography.body14(color: AppColors.primaryBlue, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _customSwitch(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? AppColors.primaryBlue : const Color(0xFFD4D4D8),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _backButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.greyBgDarker,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.arrow_back, size: 20, color: AppColors.textDark),
      ),
    );
  }
}
