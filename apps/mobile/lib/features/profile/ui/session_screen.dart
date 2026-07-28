import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../focus/data/focus_db.dart';
import '../../focus/data/focus_sync_service.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  int _focusDuration = 25;
  int _shortBreak = 5;
  int _longBreak = 15;
  int _sessionsBeforeLong = 4;
  bool _adjustDuration = false;
  bool _autoBreak = true;
  bool _autoNextSession = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await FocusDb().getProfile();
    if (!mounted) return;
    setState(() {
      if (profile != null) {
        _focusDuration = profile.focusDurationMin;
        _shortBreak = profile.shortBreakMin;
        _longBreak = profile.longBreakMin;
        _sessionsBeforeLong = profile.sessionsBeforeLongBreak;
        _adjustDuration = profile.adjustDurationAfterSession;
        _autoBreak = profile.autoStartBreak;
        _autoNextSession = profile.autoStartNextSession;
      }
      _loaded = true;
    });
  }

  Future<void> _saveDuration() async {
    await FocusDb().setPendingProfileSettings(
      focusDurationMin: _focusDuration,
      shortBreakMin: _shortBreak,
      longBreakMin: _longBreak,
      sessionsBeforeLongBreak: _sessionsBeforeLong,
    );
    FocusSyncService.instance.scheduleSync();
  }

  Future<void> _saveBehavior() async {
    await FocusDb().setPendingProfileSettings(
      adjustDurationAfterSession: _adjustDuration,
      autoStartBreak: _autoBreak,
      autoStartNextSession: _autoNextSession,
    );
    FocusSyncService.instance.scheduleSync();
  }

  void _showDurationPicker({
    required String title,
    required int current,
    required List<int> options,
    required ValueChanged<int> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.heading18()),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: options.map((v) {
                  final isSelected = v == current;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(v);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryBlue : AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primaryBlue : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '$v min',
                        style: AppTypography.body14(
                          color: isSelected ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showCountPicker({
    required String title,
    required int current,
    required List<int> options,
    required ValueChanged<int> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.heading18()),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: options.map((v) {
                  final isSelected = v == current;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(v);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryBlue : AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primaryBlue : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '$v',
                        style: AppTypography.body14(
                          color: isSelected ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
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
                  Text('Session', style: AppTypography.heading18()),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // DURATION section
            _sectionLabel('DURATION'),
            const SizedBox(height: 8),
            _card([
              _durationRow('Focus duration', '$_focusDuration min', () {
                _showDurationPicker(
                  title: 'Focus Duration',
                  current: _focusDuration,
                  options: [15, 20, 25, 30, 45, 60, 90, 120],
                  onSelected: (v) {
                    setState(() => _focusDuration = v);
                    _saveDuration();
                  },
                );
              }),
              _div(),
              _durationRow('Short break', '$_shortBreak min', () {
                _showDurationPicker(
                  title: 'Short Break',
                  current: _shortBreak,
                  options: [3, 5, 10, 15],
                  onSelected: (v) {
                    setState(() => _shortBreak = v);
                    _saveDuration();
                  },
                );
              }),
              _div(),
              _durationRow('Long break', '$_longBreak min', () {
                _showDurationPicker(
                  title: 'Long Break',
                  current: _longBreak,
                  options: [10, 15, 20, 30],
                  onSelected: (v) {
                    setState(() => _longBreak = v);
                    _saveDuration();
                  },
                );
              }),
              _div(),
              _durationRow('Sessions before long break', '$_sessionsBeforeLong', () {
                _showCountPicker(
                  title: 'Sessions Before Long Break',
                  current: _sessionsBeforeLong,
                  options: [2, 3, 4, 5, 6],
                  onSelected: (v) {
                    setState(() => _sessionsBeforeLong = v);
                    _saveDuration();
                  },
                );
              }),
            ]),
            const SizedBox(height: 20),

            // BEHAVIOR section
            _sectionLabel('BEHAVIOR'),
            const SizedBox(height: 8),
            _card([
              _toggleRow(
                title: 'Adjust duration after session',
                subtitle: 'Ask to change focus time after each session',
                value: _adjustDuration,
                onChanged: (v) {
                  setState(() => _adjustDuration = v);
                  _saveBehavior();
                },
              ),
              _div(),
              _toggleRow(
                title: 'Auto-start break',
                subtitle: 'Automatically start break timer',
                value: _autoBreak,
                onChanged: (v) {
                  setState(() => _autoBreak = v);
                  _saveBehavior();
                },
              ),
              _div(),
              _toggleRow(
                title: 'Auto-start next session',
                subtitle: 'Start focus session after break ends',
                value: _autoNextSession,
                onChanged: (v) {
                  setState(() => _autoNextSession = v);
                  _saveBehavior();
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

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

  Widget _durationRow(String label, String value, VoidCallback onTap) {
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
            Text(value, style: AppTypography.body14(color: AppColors.textMedium)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
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
          _customSwitch(value, onChanged),
        ],
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
