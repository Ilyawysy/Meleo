import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/providers/logout_controller.dart';
import '../../../core/providers/session_scope.dart';
import '../../profile/models/profile_stats.dart';
import '../../profile/providers/profile_stats_provider.dart';
import '../../profile/ui/all_time_stats_row.dart';
import '../../profile/ui/best_day_card.dart';
import '../../profile/ui/best_month_card.dart';
import '../../profile/ui/best_week_card.dart';
import '../../profile/ui/profile_hero_card.dart';
import '../../profile/ui/settings_screen.dart';
import '../../subscription/providers/subscription_provider.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  Future<void> _logout() async {
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
                Text('Signing out...'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      await ref.read(logoutControllerProvider.notifier).logout();
    } catch (_) {}
    try {
      navigator.popUntil((route) => route.isFirst);
    } catch (_) {}
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(onLogout: _logout),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated) {
      return const SizedBox.shrink();
    }

    final statsAsync = ref.watch(profileStatsProvider);
    final sub = ref.watch(subscriptionProvider);
    final isPro = sub.isPro;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(profileStatsProvider.notifier).refresh(),
          color: AppColors.primaryBlue,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(onSettings: _openSettings),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: statsAsync.when(
                    loading: () => _LoadingBody(isPro: isPro),
                    error: (_, __) => _ErrorBody(
                      onRetry: () =>
                          ref.read(profileStatsProvider.notifier).refresh(),
                    ),
                    data: (stats) => _ProfileBody(
                      stats: stats,
                      isPro: isPro,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onSettings;

  const _Header({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Center(
              child: Text('Profile', style: AppTypography.heading18()),
            ),
          ),
          GestureDetector(
            onTap: onSettings,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.settings_outlined,
                size: 20,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final ProfileStats? stats;
  final bool isPro;

  const _ProfileBody({this.stats, required this.isPro});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TODO(phase-5): wire displayName/email/createdAt once userProfileProvider is added.
        ProfileHeroCard(
          displayName: null,
          email: null,
          createdAt: null,
          isPro: isPro,
        ),
        if (stats != null) ...[
          const SizedBox(height: 24),
          Text(
            'All-time stats',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          AllTimeStatsRow(
            allFocusSeconds: stats!.allFocusSeconds,
            daysInApp: stats!.daysInApp,
            longestStreak: stats!.longestStreak,
          ),
          const SizedBox(height: 24),
          Text(
            'Personal records',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          BestDayCard(bestDay: stats!.bestDay),
          const SizedBox(height: 12),
          BestWeekCard(bestWeek: stats!.bestWeek),
          const SizedBox(height: 12),
          BestMonthCard(bestMonth: stats!.bestMonth),
          const SizedBox(height: 24),
        ] else ...[
          const SizedBox(height: 40),
          Center(
            child: Text(
              'No stats yet.\nStart a focus session!',
              textAlign: TextAlign.center,
              style: AppTypography.body15(color: AppColors.textLight),
            ),
          ),
        ],
      ],
    );
  }
}

class _LoadingBody extends StatelessWidget {
  final bool isPro;

  const _LoadingBody({required this.isPro});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileHeroCard(isPro: isPro),
        const SizedBox(height: 24),
        _shimmerBox(height: 16, width: 120),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _shimmerBox(height: 90)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 90)),
            const SizedBox(width: 10),
            Expanded(child: _shimmerBox(height: 90)),
          ],
        ),
        const SizedBox(height: 24),
        _shimmerBox(height: 16, width: 140),
        const SizedBox(height: 12),
        _shimmerBox(height: 90),
        const SizedBox(height: 12),
        _shimmerBox(height: 120),
        const SizedBox(height: 12),
        _shimmerBox(height: 140),
      ],
    );
  }

  Widget _shimmerBox({double height = 20, double? width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(
              'Failed to load profile stats',
              style: AppTypography.body15(color: AppColors.textMedium),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Retry',
                  style: AppTypography.body14(
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
