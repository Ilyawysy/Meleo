import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/preferences/onboarding_preferences.dart';
import '../../../core/providers/session_scope.dart';
import '../data/onboarding_service.dart';
import '../../focus/constants/room_colors.dart';
import '../../focus/data/focus_db.dart';
import '../../focus/data/focus_room_db.dart';
import '../../focus/data/focus_room_sync_service.dart';
import '../../focus/data/focus_sync_service.dart';
import '../../focus/models/focus_room.dart';
import '../../notifications/services/local_notification_service.dart';
import '../../../core/preferences/settings_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0; // 0-5 = 6 steps
  bool _isSubmitting = false;

  // Step 2: Daily goal
  int _dailyGoal = 60;

  // Step 3: Focus days
  final Map<int, bool> _dayEnabled = {1: true, 2: true, 3: true, 4: true, 5: true, 6: false, 7: false};
  final Map<int, int> _dayMinutes = {1: 60, 2: 60, 3: 60, 4: 60, 5: 60, 6: 60, 7: 60};

  // Step 4: Notifications
  bool _notificationsEnabled = false;

  // Step 5: First room name
  String _firstRoomName = '';

  void _next() {
    if (_step < 5) {
      setState(() => _step++);
    }
  }

  void _skip() => _next();

  Future<void> _finish({required String roomName}) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      // Save plan to server
      final planMinutes = <int, int>{};
      for (int d = 1; d <= 7; d++) {
        planMinutes[d] = _dayEnabled[d]! ? _dayMinutes[d]! : 0;
      }
      await FocusDb().setPendingProfileSettings(planMinutes: planMinutes);
      FocusSyncService.instance.scheduleSync();

      // Save notification preference
      await SettingsPreferences.setNotificationsEnabled(_notificationsEnabled);

      // Create focus room locally if user provided a name.
      if (roomName.isNotEmpty) {
        final room = FocusRoom.create(
          title: roomName,
          color: kRoomColorPalette.first,
        );
        await FocusRoomDb().create(room);
        FocusRoomSyncService.instance.scheduleSync();
      }

      // Mark onboarding done locally and on server
      final userId = ref.read(sessionScopeProvider).userId;
      if (userId != null) {
        await OnboardingPreferences.markCompletedForUser(userId);
        final success = await OnboardingService.markCompletedOnServer();
        if (!success) {
          await OnboardingPreferences.markPendingSyncForUser(userId);
        }
      }

      widget.onComplete();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      0 => _WelcomeStep(key: const ValueKey(0), onContinue: _next),
      1 => _DailyGoalStep(
          key: const ValueKey(1),
          selected: _dailyGoal,
          onSelected: (v) => setState(() => _dailyGoal = v),
          onContinue: () {
            // Apply daily goal to all enabled days
            for (int d = 1; d <= 7; d++) {
              _dayMinutes[d] = _dailyGoal;
            }
            _next();
          },
          onSkip: _skip,
        ),
      2 => _FocusDaysStep(
          key: const ValueKey(2),
          dayEnabled: _dayEnabled,
          dayMinutes: _dayMinutes,
          onToggleDay: (d) => setState(() => _dayEnabled[d] = !_dayEnabled[d]!),
          onAdjust: (d, delta) => setState(() {
                final cur = _dayMinutes[d]!;
                _dayMinutes[d] = (cur + delta).clamp(10, 480);
              }),
          onContinue: _next,
          onSkip: _skip,
        ),
      3 => _NotificationsStep(
          key: const ValueKey(3),
          onEnable: () async {
            setState(() => _notificationsEnabled = true);
            await SettingsPreferences.setNotificationsEnabled(true);
            // Request system permission
            await LocalNotificationService().initialize();
            _next();
          },
          onSkip: () {
            setState(() => _notificationsEnabled = false);
            _next();
          },
        ),
      4 => _FirstRoomStep(
          key: const ValueKey(4),
          initialName: _firstRoomName,
          isSubmitting: _isSubmitting,
          onContinue: (name) {
            setState(() => _firstRoomName = name);
            _next();
          },
          onSkip: () {
            setState(() => _firstRoomName = '');
            // Skip both the room step and the next (Ready/task) step,
            // since first-task creation is tied to the room being created.
            _finish(roomName: '');
          },
        ),
      5 => _ReadyStep(
          key: const ValueKey(5),
          dailyGoal: _dailyGoal,
          dayEnabled: _dayEnabled,
          notificationsEnabled: _notificationsEnabled,
          firstRoomName: _firstRoomName,
          isSubmitting: _isSubmitting,
          onCreateTask: () => _finish(roomName: _firstRoomName),
          onExplore: () => _finish(roomName: _firstRoomName),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

// =============================================================================
// Step 1: Welcome
// =============================================================================
class _WelcomeStep extends StatelessWidget {
  final VoidCallback onContinue;
  const _WelcomeStep({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
      child: Column(
        children: [
          const Spacer(flex: 1),
          // Logo
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.center_focus_strong, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to Meleo',
            style: AppTypography.heading30(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Your productivity companion that helps you plan, focus, and track your progress.',
            style: AppTypography.body15(color: AppColors.textMedium).copyWith(height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // Feature cards
          _featureCard(Icons.checklist, 'Plan',
              'Organize tasks by priority and schedule your day effortlessly'),
          const SizedBox(height: 16),
          _featureCard(Icons.timer_outlined, 'Focus',
              'Deep work sessions with a distraction-free timer and ambient sounds'),
          const SizedBox(height: 16),
          _featureCard(Icons.trending_up, 'Track',
              'See your progress, earn XP, and build lasting productive habits'),
          const Spacer(flex: 2),
          // Dots
          _dots(0),
          const SizedBox(height: 32),
          // Button
          _primaryButton('Get Started', onContinue),
        ],
      ),
    );
  }

  Widget _featureCard(IconData icon, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: AppColors.primaryBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.heading18()),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: AppTypography.body13(color: AppColors.textMedium).copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 2: Daily Goal
// =============================================================================
class _DailyGoalStep extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const _DailyGoalStep({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
      child: Column(
        children: [
          const Spacer(flex: 1),
          const Text('🎯', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 28),
          Text(
            'Set your daily goal',
            style: AppTypography.heading30().copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'How many minutes of focused work do you want to achieve each day?',
            style: AppTypography.body15(color: AppColors.textMedium).copyWith(height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Goal grid
          Row(
            children: [
              Expanded(child: _goalCard(30)),
              const SizedBox(width: 12),
              Expanded(child: _goalCard(60)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _goalCard(90)),
              const SizedBox(width: 12),
              Expanded(child: _goalCard(120)),
            ],
          ),
          const Spacer(flex: 2),
          // Buttons
          _primaryButton('Continue', onContinue),
          const SizedBox(height: 16),
          _dots(1),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onSkip,
            child: Text(
              'Skip for now',
              style: AppTypography.body14(color: AppColors.textLight, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goalCard(int minutes) {
    final isSelected = selected == minutes;
    return GestureDetector(
      onTap: () => onSelected(minutes),
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : AppColors.greyBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$minutes',
              style: AppTypography.heading30().copyWith(
                fontSize: 32,
                color: isSelected ? AppColors.primaryBlue : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'minutes',
              style: AppTypography.body13(
                color: isSelected ? AppColors.primaryBlue : AppColors.textMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Step 3: Focus Days
// =============================================================================
class _FocusDaysStep extends StatelessWidget {
  final Map<int, bool> dayEnabled;
  final Map<int, int> dayMinutes;
  final ValueChanged<int> onToggleDay;
  final void Function(int day, int delta) onAdjust;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  const _FocusDaysStep({
    super.key,
    required this.dayEnabled,
    required this.dayMinutes,
    required this.onToggleDay,
    required this.onAdjust,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final activeDays = <int>[];
    for (int d = 1; d <= 7; d++) {
      if (dayEnabled[d]!) activeDays.add(d);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
      child: Column(
        children: [
          const Text('📅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 28),
          Text(
            'Choose your focus days',
            style: AppTypography.heading30().copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Which days do you want to commit to focused work?',
            style: AppTypography.body15(color: AppColors.textMedium).copyWith(height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Day circles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final d = i + 1;
              final active = dayEnabled[d]!;
              return GestureDetector(
                onTap: () => onToggleDay(d),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.primaryBlue : null,
                    border: active ? null : Border.all(color: AppColors.border, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      _letters[i],
                      style: AppTypography.body14(
                        color: active ? Colors.white : AppColors.textSlateLight,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          // Time schedule for active days
          if (activeDays.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Focus time per day',
                style: AppTypography.body13(
                  color: AppColors.textSlate,
                  fontWeight: FontWeight.w600,
                ).copyWith(letterSpacing: 0.3),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                children: activeDays.map((d) => _dayRow(d)).toList(),
              ),
            ),
          ] else
            const Expanded(child: SizedBox()),
          Text(
            'Tap days to toggle on/off. Use +/\u2212 to adjust focus time. You can change this later in Settings.',
            style: AppTypography.body13(color: AppColors.textLight),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _primaryButton('Continue', onContinue),
          const SizedBox(height: 16),
          _dots(2),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onSkip,
            child: Text(
              'Skip for now',
              style: AppTypography.body14(color: AppColors.textLight, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(int d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _names[d - 1],
            style: AppTypography.body13(color: AppColors.primaryBlue, fontWeight: FontWeight.w600),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepperBtn(Icons.remove, () => onAdjust(d, -10)),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: Text(
                  '${dayMinutes[d]} min',
                  style: AppTypography.body13(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              _stepperBtn(Icons.add, () => onAdjust(d, 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn(IconData icon, VoidCallback onTap) {
    final isPlus = icon == Icons.add;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          icon,
          size: 12,
          color: isPlus ? AppColors.primaryBlue : AppColors.textSlateLight,
        ),
      ),
    );
  }
}

// =============================================================================
// Step 4: Notifications
// =============================================================================
class _NotificationsStep extends StatelessWidget {
  final VoidCallback onEnable;
  final VoidCallback onSkip;

  const _NotificationsStep({
    super.key,
    required this.onEnable,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
      child: Column(
        children: [
          const Spacer(flex: 1),
          // Bell icon
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(48),
            ),
            child: const Icon(Icons.notifications_outlined, color: AppColors.primaryBlue, size: 44),
          ),
          const SizedBox(height: 28),
          Text(
            'Stay on track',
            style: AppTypography.heading30().copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Get gentle reminders for your focus\nsessions and task deadlines.',
            style: AppTypography.body15(color: AppColors.textSlate).copyWith(height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Feature benefits
          _benefit(
            const Color(0xFFF0FDF4),
            Icons.check_circle_outline,
            const Color(0xFF16A34A),
            'Focus session reminders',
          ),
          const SizedBox(height: 18),
          _benefit(
            const Color(0xFFEFF6FF),
            Icons.alarm,
            AppColors.primaryBlue,
            'Task deadline alerts',
          ),
          const SizedBox(height: 18),
          _benefit(
            const Color(0xFFFEF3C7),
            Icons.shield_outlined,
            const Color(0xFFD97706),
            'Streak protection',
          ),
          const Spacer(flex: 2),
          _dots(3),
          const SizedBox(height: 28),
          // Enable button
          _solidBlueButton('Enable notifications', onEnable),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onSkip,
            child: Text(
              'Maybe later',
              style: AppTypography.body14(color: AppColors.textSlateLight, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefit(Color bg, IconData icon, Color iconColor, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Text(text, style: AppTypography.body15(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 5: First Room Name
// =============================================================================
class _FirstRoomStep extends StatefulWidget {
  final String initialName;
  final bool isSubmitting;
  final void Function(String name) onContinue;
  final VoidCallback onSkip;

  const _FirstRoomStep({
    super.key,
    required this.initialName,
    required this.isSubmitting,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  State<_FirstRoomStep> createState() => _FirstRoomStepState();
}

class _FirstRoomStepState extends State<_FirstRoomStep> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty || name.length > 120) return;
    widget.onContinue(name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 34,
      ),
      child: Column(
        children: [
          const Spacer(flex: 1),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(48),
            ),
            child: const Icon(Icons.meeting_room_outlined, color: AppColors.primaryBlue, size: 44),
          ),
          const SizedBox(height: 28),
          Text(
            'Create your first focus room',
            style: AppTypography.heading30().copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Give it a name like "Work", "Study", or "Side Project"',
            style: AppTypography.body15(color: AppColors.textMedium).copyWith(height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            style: AppTypography.body15(),
            decoration: InputDecoration(
              hintText: 'Room name',
              hintStyle: AppTypography.body15(color: AppColors.textLight),
              counterText: '',
              filled: true,
              fillColor: AppColors.greyBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const Spacer(flex: 2),
          _dots(4),
          const SizedBox(height: 28),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _ctrl,
            builder: (context, value, _) {
              final enabled = value.text.trim().isNotEmpty && !widget.isSubmitting;
              return GestureDetector(
                onTap: enabled ? _submit : null,
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: enabled
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                          )
                        : null,
                    color: enabled ? null : const Color(0xFFD4D4D8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: widget.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Create Room',
                            style: AppTypography.body15(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ).copyWith(fontSize: 16),
                          ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: widget.isSubmitting ? null : widget.onSkip,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Skip for now',
                style: AppTypography.body14(
                  color: widget.isSubmitting
                      ? AppColors.textLight
                      : AppColors.textSlateLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Step 6: Ready
// =============================================================================
class _ReadyStep extends StatelessWidget {
  final int dailyGoal;
  final Map<int, bool> dayEnabled;
  final bool notificationsEnabled;
  final String firstRoomName;
  final bool isSubmitting;
  final VoidCallback onCreateTask;
  final VoidCallback onExplore;

  const _ReadyStep({
    super.key,
    required this.dailyGoal,
    required this.dayEnabled,
    required this.notificationsEnabled,
    required this.firstRoomName,
    required this.isSubmitting,
    required this.onCreateTask,
    required this.onExplore,
  });

  String get _focusDaysSummary {
    final active = <int>[];
    for (int d = 1; d <= 7; d++) {
      if (dayEnabled[d]!) active.add(d);
    }
    if (active.isEmpty) return 'None';
    if (active.length == 7) return 'Every day';
    if (active.length == 5 && !active.contains(6) && !active.contains(7)) {
      return 'Mon \u2013 Fri';
    }
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return active.map((d) => names[d - 1]).join(', ');
  }

  String get _goalText {
    if (dailyGoal >= 60) {
      final h = dailyGoal ~/ 60;
      final m = dailyGoal % 60;
      if (m == 0) return '$h ${h == 1 ? 'hour' : 'hours'}';
      return '${h}h ${m}m';
    }
    return '$dailyGoal minutes';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        children: [
          const SizedBox(height: 60),
          // Check icon
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(48),
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 48),
          ),
          const SizedBox(height: 24),
          Text(
            "You're all set!",
            style: AppTypography.heading30().copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "Here's a summary of your setup.",
            style: AppTypography.body15(color: AppColors.textSlate),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Summary card
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.greyBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _summaryRow('Daily goal', _goalText),
                Container(height: 1, color: const Color(0xFFE5E7EB)),
                _summaryRow('Focus days', _focusDaysSummary),
                Container(height: 1, color: const Color(0xFFE5E7EB)),
                _summaryRow(
                  'Notifications',
                  notificationsEnabled ? 'Enabled' : 'Disabled',
                  valueColor: notificationsEnabled ? const Color(0xFF16A34A) : AppColors.textLight,
                ),
                if (firstRoomName.isNotEmpty) ...[
                  Container(height: 1, color: const Color(0xFFE5E7EB)),
                  _summaryRow('First room', firstRoomName),
                ],
              ],
            ),
          ),
          const Spacer(),
          _dots(5),
          const SizedBox(height: 20),
          // Create task button
          GestureDetector(
            onTap: isSubmitting ? null : onCreateTask,
            child: Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                color: isSubmitting ? AppColors.textLight : AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSubmitting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else
                    const Icon(Icons.add, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Create your first task',
                    style: AppTypography.body15(color: Colors.white, fontWeight: FontWeight.w600)
                        .copyWith(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: isSubmitting ? null : onExplore,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Explore the app first',
                style: AppTypography.body14(
                  color: isSubmitting ? AppColors.textLight : AppColors.textSlateLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.body14(color: AppColors.textSlate, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: AppTypography.body14(
              color: valueColor ?? AppColors.textDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Shared widgets
// =============================================================================
Widget _dots(int activeIndex) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(6, (i) {
      return Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i == activeIndex ? AppColors.primaryBlue : const Color(0xFFD4D4D8),
        ),
      );
    }),
  );
}

Widget _primaryButton(String label, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          label,
          style: AppTypography.body15(color: Colors.white, fontWeight: FontWeight.w600)
              .copyWith(fontSize: 16),
        ),
      ),
    ),
  );
}

Widget _solidBlueButton(String label, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          label,
          style: AppTypography.body15(color: Colors.white, fontWeight: FontWeight.w600)
              .copyWith(fontSize: 16),
        ),
      ),
    ),
  );
}
