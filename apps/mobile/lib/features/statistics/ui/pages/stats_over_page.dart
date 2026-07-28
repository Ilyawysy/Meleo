import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../subscription/providers/subscription_provider.dart';
import '../../../subscription/ui/pro_upgrade_sheet.dart';
import '../../providers/statistics_provider.dart';
import '../../models/statistics_state.dart';

// Local color constants
const _colorGreen = Color(0xFF16A34A);
const _colorAmber = Color(0xFFF59E0B);
const _colorRed = Color(0xFFDC2626);
const _colorPurple = Color(0xFF4F46E5);
const _colorPurpleDark = Color(0xFF7C3AED);
const _colorPurpleLight = Color(0xFFA5B4FC);
const _colorCardBg = Color(0xFFF8F8FA);
const _colorPillBg = Color(0xFFF4F4F5);
const _colorBorder = Color(0xFFE5E7EB);
const _colorTextDark = Color(0xFF18181B);
const _colorTextMid = Color(0xFF64748B);
const _colorTextLight = Color(0xFF94A3B8);
const _colorTextLighter = Color(0xFFA1A1AA);

class StatsOverPage extends ConsumerWidget {
  const StatsOverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statisticsProvider);
    final isPro = ref.watch(subscriptionProvider).isPro;

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Не удалось загрузить')),
      data: (stats) => _buildContent(context, stats, isPro),
    );
  }

  Widget _buildContent(BuildContext context, StatisticsState stats, bool isPro) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        _FocusFormSection(stats: stats),
        const SizedBox(height: 22),
        _WeekExecutionSection(stats: stats),
        const SizedBox(height: 22),
        if (!isPro) ...[
          _AllStatsProCard(onTap: () => _showUpgradeSheet(context)),
          const SizedBox(height: 22),
        ],
      ],
    );
  }

  void _showUpgradeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProUpgradeSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Section 1: Focus Form
// ─────────────────────────────────────────────────────────────

class _FocusFormSection extends StatelessWidget {
  final StatisticsState stats;
  const _FocusFormSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Focus Form',
          trailing: _PillLabel(label: 'This week', showChevron: true),
        ),
        const SizedBox(height: 12),
        _FormCard(
          formScore: stats.formScore,
          formScorePrev: stats.formScorePrev,
          formTrend: stats.formTrend,
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  final int formScore;
  final int formScorePrev;
  final String formTrend;

  const _FormCard({
    required this.formScore,
    required this.formScorePrev,
    required this.formTrend,
  });

  Color _scoreColor(int score) {
    if (score >= 70) return _colorGreen;
    if (score >= 40) return _colorAmber;
    return _colorRed;
  }

  String _trendLabel(String trend) {
    switch (trend) {
      case 'rising':
        return '↗ Rising';
      case 'falling':
        return '↘ Falling';
      default:
        return '→ Stable';
    }
  }

  bool _isPositiveTrend(String trend) => trend != 'falling';

  String _deltaText() {
    final delta = (formScore - formScorePrev) / 10.0;
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)} vs last week';
  }

  @override
  Widget build(BuildContext context) {
    final scoreVal = formScore / 10.0;
    final scoreColor = _scoreColor(formScore);
    final trendLabel = _trendLabel(formTrend);
    final positive = _isPositiveTrend(formTrend);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _colorCardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left column: score
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: scoreVal.toStringAsFixed(1),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: scoreColor,
                        letterSpacing: -0.5,
                        height: 1,
                      ),
                    ),
                    TextSpan(
                      text: '/10',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _colorTextLight,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Focus Form',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _colorTextMid,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Right column: badge + delta
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: positive ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  trendLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: positive ? _colorGreen : _colorRed,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _deltaText(),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: _colorTextLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Section 2: Week Execution
// ─────────────────────────────────────────────────────────────

class _WeekExecutionSection extends StatelessWidget {
  final StatisticsState stats;
  const _WeekExecutionSection({required this.stats});

  String _weekRangeLabel() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon, 7=Sun
    final monday = now.subtract(Duration(days: weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final fromStr = '${monday.day} ${months[monday.month - 1]}';
    final toStr = '${sunday.day} ${months[sunday.month - 1]}';
    return '$fromStr - $toStr';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Week Execution',
          trailing: Text(
            _weekRangeLabel(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _colorTextLighter,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _WeekExecutionCard(stats: stats),
      ],
    );
  }
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

class _WeekExecutionCard extends StatelessWidget {
  final StatisticsState stats;
  const _WeekExecutionCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final factTotal = stats.planVsFactWeekTotal;
    final planTotal = stats.planVsFactWeekPlanTotal;
    final pct = planTotal > 0 ? (factTotal / planTotal).clamp(0.0, 1.0) : 0.0;
    final pctInt = (pct * 100).round();
    final planHours = (planTotal / 60.0).round();
    final remaining = (planTotal - factTotal).clamp(0, planTotal);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _colorCardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: fact/plan + pct
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: _formatMinutes(factTotal),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _colorTextDark,
                        height: 1,
                      ),
                    ),
                    TextSpan(
                      text: ' /${planHours}h',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _colorTextLight,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '$pctInt%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _colorPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                  height: 8,
                  color: _colorBorder,
                ),
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    height: 8,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_colorPurple, _colorPurpleDark],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatMinutes(remaining)} left',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _colorTextMid,
            ),
          ),
          const SizedBox(height: 14),
          // Daily bars
          _DailyBars(planVsFactWeek: stats.planVsFactWeek),
        ],
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  final Map<int, ({int plan, int fact})> planVsFactWeek;
  const _DailyBars({required this.planVsFactWeek});

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1=Mon, 7=Sun

    // Find max fact to scale bars
    int maxFact = 0;
    for (int wd = 1; wd <= 7; wd++) {
      final entry = planVsFactWeek[wd];
      if (entry != null && entry.fact > maxFact) maxFact = entry.fact;
    }
    if (maxFact == 0) maxFact = 1;

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final weekday = i + 1; // 1=Mon..7=Sun
          final entry = planVsFactWeek[weekday];
          final fact = entry?.fact ?? 0;
          final isToday = weekday == todayWeekday;
          final isPast = weekday < todayWeekday;
          final barHeight = ((fact / maxFact) * 64).clamp(isToday || isPast ? 8.0 : 4.0, 64.0);

          return _DayBar(
            label: _dayLabels[i],
            barHeight: barHeight,
            isToday: isToday,
            hasFact: fact > 0,
            isFuture: weekday > todayWeekday,
          );
        }),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final String label;
  final double barHeight;
  final bool isToday;
  final bool hasFact;
  final bool isFuture;

  const _DayBar({
    required this.label,
    required this.barHeight,
    required this.isToday,
    required this.hasFact,
    required this.isFuture,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar;
    if (isToday) {
      bar = Container(
        width: 28,
        height: barHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            colors: [_colorPurple, _colorPurpleDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      );
    } else if (!isFuture && hasFact) {
      bar = Container(
        width: 28,
        height: barHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _colorPurpleLight,
        ),
      );
    } else {
      bar = Container(
        width: 28,
        height: barHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _colorBorder,
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        bar,
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            color: isToday ? _colorPurple : _colorTextLight,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Section 3: All Stats PRO card
// ─────────────────────────────────────────────────────────────

class _AllStatsProCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AllStatsProCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'All Stats',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _colorTextDark,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    size: 12,
                    color: _colorAmber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'PRO',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _colorAmber,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [_colorPurple, _colorPurpleDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unlock deep insights',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Focus, Rooms & Compare tabs',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xCCFFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get PRO',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _colorPurple,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: _colorPurple,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _colorTextDark,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _PillLabel extends StatelessWidget {
  final String label;
  final bool showChevron;
  const _PillLabel({required this.label, this.showChevron = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _colorPillBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _colorTextMid,
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 12, color: _colorTextLight),
          ],
        ],
      ),
    );
  }
}
