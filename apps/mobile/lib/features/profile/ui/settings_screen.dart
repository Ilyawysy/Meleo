import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/logout_controller.dart';
import '../../focus/data/focus_db.dart';
import '../../focus/data/focus_sync_service.dart';
import '../../focus/providers/focus_provider.dart';
import '../../subscription/providers/subscription_provider.dart';
import 'delete_account_dialog.dart';
import 'schedule_screen.dart';
import 'session_screen.dart';
import 'sound_screen.dart';
import 'reminders_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLogout;

  const SettingsScreen({super.key, this.onLogout});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _minimalMode = false;
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
      _minimalMode = profile?.minimalMode ?? false;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final themeAsync = ref.watch(themeProvider);
    final themeMode = themeAsync.valueOrNull ?? ThemeMode.system;
    final themeName = switch (themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      _ => 'System',
    };

    final focusData = ref.watch(focusProvider);
    final profile = focusData?.profile;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            // Nav header
            _buildNav(context),
            const SizedBox(height: 14),

            // --- PRO banner ---
            _buildProBanner(),
            const SizedBox(height: 14),

            // --- FOCUS section ---
            _sectionLabel('FOCUS'),
            const SizedBox(height: 8),
            _card([
              _rowItem(
                icon: Icons.calendar_today_outlined,
                label: 'Schedule',
                value: _scheduleSubtitle(profile),
                onTap: () => _push(const ScheduleScreen()),
              ),
              _divider(),
              _rowItem(
                icon: Icons.timer_outlined,
                label: 'Session',
                value: '${profile?.focusDurationMin ?? 25} min',
                onTap: () => _push(const SessionScreen()),
              ),
              _divider(),
              _rowItem(
                icon: Icons.volume_up_outlined,
                label: 'Sound',
                value: '',
                onTap: () => _push(const SoundScreen()),
              ),
            ]),
            const SizedBox(height: 14),

            // --- GAMIFICATION section ---
            _sectionLabel('GAMIFICATION'),
            const SizedBox(height: 8),
            _card([
              _toggleRow(
                title: 'Minimal Mode',
                subtitle: 'Only XP, no coins or streaks',
                value: _minimalMode,
                onChanged: (v) async {
                  setState(() => _minimalMode = v);
                  await FocusDb().setPendingProfileSettings(minimalMode: v);
                  FocusSyncService.instance.scheduleSync();
                },
              ),
            ]),
            const SizedBox(height: 14),

            // --- REMINDERS section ---
            _sectionLabel('REMINDERS'),
            const SizedBox(height: 8),
            _card([
              _rowItem(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                showChevron: true,
                onTap: () => _push(const RemindersScreen()),
              ),
            ]),
            const SizedBox(height: 14),

            // --- GENERAL section ---
            _sectionLabel('GENERAL'),
            const SizedBox(height: 8),
            _card([
              _rowItem(
                icon: Icons.palette_outlined,
                label: 'Theme',
                value: themeName,
                onTap: _showThemePicker,
              ),
              _divider(),
              _rowItem(
                icon: Icons.language_outlined,
                label: 'Language',
                value: 'English',
                onTap: () {},
              ),
              _divider(),
              _rowItem(
                icon: Icons.shield_outlined,
                label: 'Data & Privacy',
                showChevron: true,
                onTap: () {},
              ),
              _divider(),
              _rowItem(
                icon: Icons.info_outline,
                label: 'About',
                value: 'v1.0.0',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 14),

            // --- ACCOUNT section ---
            _sectionLabel('ACCOUNT'),
            const SizedBox(height: 8),
            _card([
              _rowItem(
                icon: Icons.logout,
                label: 'Log Out',
                iconColor: AppColors.textDark,
                onTap: () => _confirmLogout(context),
              ),
              _divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const DeleteAccountDialog(),
                    ),
                    child: Text(
                      'Delete Account',
                      style: AppTypography.body14(
                        color: AppColors.errorDark,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Nav ──
  Widget _buildNav(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _backButton(context),
          Text('Settings', style: AppTypography.heading18()),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _backButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.arrow_back, size: 20, color: AppColors.textDark),
      ),
    );
  }

  // ── Pro banner ──
  Widget _buildProBanner() {
    final sub = ref.watch(subscriptionProvider);
    final isPro = sub.isPro;
    return GestureDetector(
      onTap: () {
        // TODO: navigate to subscription management
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, size: 22, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meleo Pro',
                    style: AppTypography.body15(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isPro ? 'Pro plan · Active' : 'Free plan · Upgrade for AI chat',
                    style: AppTypography.caption12(color: const Color(0xFFFFFFCC)),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: Color(0xFFFFFF99),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section label ──
  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.caption12(color: AppColors.textLight).copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  // ── Card container ──
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

  Widget _divider() {
    return Container(height: 1, color: AppColors.divider);
  }

  // ── Row item ──
  Widget _rowItem({
    required IconData icon,
    required String label,
    String? value,
    bool showChevron = false,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.textLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: AppTypography.body15(fontWeight: FontWeight.w500)),
            ),
            if (value != null && value.isNotEmpty)
              Text(value, style: AppTypography.body14(color: AppColors.textLight)),
            if (showChevron || (value == null && !showChevron))
              ...[],
            if (showChevron)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right, size: 16, color: AppColors.textLight),
              ),
            if (value != null && value.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right, size: 16, color: AppColors.textLight),
              ),
          ],
        ),
      ),
    );
  }

  // ── Toggle row ──
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

  // ── Helpers ──
  String _scheduleSubtitle(dynamic profile) {
    if (profile == null) return '5 days';
    final planMinutes = profile.planMinutes as Map<int, int>?;
    if (planMinutes == null) return '5 days';
    final activeDays = planMinutes.values.where((v) => v > 0).length;
    return '$activeDays days';
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) {
      _load(); // reload after returning from sub-screen
    });
  }

  void _showThemePicker() {
    final themeAsync = ref.read(themeProvider);
    final current = themeAsync.valueOrNull ?? ThemeMode.system;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              (ThemeMode.system, 'System', Icons.brightness_auto),
              (ThemeMode.light, 'Light', Icons.light_mode),
              (ThemeMode.dark, 'Dark', Icons.dark_mode),
            ])
              ListTile(
                leading: Icon(entry.$3),
                title: Text(entry.$2),
                trailing: current == entry.$1
                    ? const Icon(Icons.check, color: AppColors.primaryBlue)
                    : null,
                onTap: () {
                  ref.read(themeProvider.notifier).setThemeMode(entry.$1);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Log Out', style: AppTypography.heading20()),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to log out?',
                  style: AppTypography.body15(color: AppColors.textMedium),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Cancel',
                      style: AppTypography.body15(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _performLogout();
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Log Out',
                      style: AppTypography.body15(
                        color: AppColors.errorDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _performLogout() async {
    if (widget.onLogout != null) {
      widget.onLogout!();
      return;
    }
    // Fallback: call LogoutController directly when no callback provided
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Выход...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await ref.read(logoutControllerProvider.notifier).logout();
    } catch (e) {
      debugPrint('[SettingsScreen] Logout error: $e');
    }

    try {
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('[SettingsScreen] Navigation after logout failed: $e');
    }
  }
}
