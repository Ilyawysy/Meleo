import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/statistics_provider.dart';

String _formatDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String _weekdayLabel(int weekday) =>
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

String _shortMonth(int month) => [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][month - 1];

DateTime _mondayOf(DateTime d) =>
    d.subtract(Duration(days: d.weekday - 1));

String _fmtDate(DateTime d) => '${d.day} ${_shortMonth(d.month)}';

class StatsFocusPage extends ConsumerWidget {
  const StatsFocusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statisticsProvider);
    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Не удалось загрузить')),
      data: (stats) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlanVsFactSection(planVsFactWeek: stats.planVsFactWeek),
            const SizedBox(height: 24),
            _SummaryCardsRow(
              planCompletePct: stats.thisWeekSummary.planCompletePct,
              allFocusMinutes: stats.thisWeekSummary.allFocusMinutes,
              avgFocusMinutesPerDay:
                  stats.thisWeekSummary.avgFocusMinutesPerDay,
            ),
            const SizedBox(height: 24),
            _TwoInfoCards(
              sessions: stats.thisWeekSummary.sessions,
              focusDays: stats.thisWeekSummary.focusDays,
              focusDaysGoal: stats.thisWeekSummary.focusDaysGoal,
            ),
            const SizedBox(height: 24),
            _SessionsSection(
              hourlyMinutes: stats.hourlyMinutes,
              bestFocusWindow: stats.bestFocusWindow,
              avgFocusPerSession:
                  stats.thisWeekSummary.avgFocusMinutesPerSession,
              avgFocusPerDay: stats.thisWeekSummary.avgFocusMinutesPerDay,
            ),
            const SizedBox(height: 24),
            _ScreenTimeSection(
              screenTimeTotalMinutes: stats.screenTimeTotalMinutes,
              screenTimeDuringFocus: stats.screenTimeDuringFocus,
              screenTimeAfterFocus: stats.screenTimeAfterFocus,
              appUsage: stats.appUsage,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan vs Fact
// ---------------------------------------------------------------------------

class _PlanVsFactSection extends StatefulWidget {
  final Map<int, ({int plan, int fact})> planVsFactWeek;
  const _PlanVsFactSection({required this.planVsFactWeek});

  @override
  State<_PlanVsFactSection> createState() => _PlanVsFactSectionState();
}

class _PlanVsFactSectionState extends State<_PlanVsFactSection> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = _mondayOf(now);
    final sunday = monday.add(const Duration(days: 6));
    final headerDate = '${_fmtDate(monday)} - ${_fmtDate(sunday)}';

    final data = widget.planVsFactWeek;
    int maxVal = 1;
    for (int d = 1; d <= 7; d++) {
      final e = data[d];
      if (e != null) {
        if (e.plan > maxVal) maxVal = e.plan;
        if (e.fact > maxVal) maxVal = e.fact;
      }
    }
    final todayWd = now.weekday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Plan vs Fact',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF18181B),
              ),
            ),
            _SegmentPill(
              labels: const ['W', 'M'],
              selected: _selected,
              onChanged: (v) => setState(() => _selected = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8FA),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    headerDate,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF18181B),
                    ),
                  ),
                  Row(
                    children: [
                      _LegendSquare(
                          color: const Color(0xFF4F46E5), label: 'Fact'),
                      const SizedBox(width: 6),
                      _LegendSquare(
                          color: const Color(0xFFE5E7EB), label: 'Plan'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (idx) {
                      final wd = idx + 1;
                      final e = data[wd];
                      final plan = e?.plan ?? 0;
                      final fact = e?.fact ?? 0;
                      final planH =
                          (plan / maxVal * 110).clamp(4.0, 110.0);
                      final factH =
                          (fact / maxVal * 110).clamp(4.0, 110.0);
                      final isToday = wd == todayWd;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 12,
                                height: planH,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Container(
                                width: 12,
                                height: factH,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF4F46E5),
                                      Color(0xFF7C3AED),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _weekdayLabel(wd).substring(0, 2),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isToday
                                  ? const Color(0xFF4F46E5)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary cards row
// ---------------------------------------------------------------------------

class _SummaryCardsRow extends StatelessWidget {
  final int planCompletePct;
  final int allFocusMinutes;
  final int avgFocusMinutesPerDay;

  const _SummaryCardsRow({
    required this.planCompletePct,
    required this.allFocusMinutes,
    required this.avgFocusMinutesPerDay,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStatCard(
            value: '$planCompletePct%',
            valueColor: const Color(0xFF4F46E5),
            label: 'Plan Complete',
            valueFontSize: 22,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStatCard(
            value: _formatDuration(allFocusMinutes),
            valueColor: const Color(0xFF18181B),
            label: 'All Focus',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStatCard(
            value: _formatDuration(avgFocusMinutesPerDay),
            valueColor: const Color(0xFF18181B),
            label: 'Avg Focus / d',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Two info cards
// ---------------------------------------------------------------------------

class _TwoInfoCards extends StatelessWidget {
  final int sessions;
  final int focusDays;
  final int focusDaysGoal;

  const _TwoInfoCards({
    required this.sessions,
    required this.focusDays,
    required this.focusDaysGoal,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FA),
              borderRadius: BorderRadius.circular(16),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$sessions',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF4F46E5),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sessions',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF18181B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'this week',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FA),
              borderRadius: BorderRadius.circular(16),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$focusDays / $focusDaysGoal',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF18181B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Closed Focus Days',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sessions section
// ---------------------------------------------------------------------------

class _SessionsSection extends StatefulWidget {
  final Map<int, int> hourlyMinutes;
  final String bestFocusWindow;
  final double avgFocusPerSession;
  final int avgFocusPerDay;

  const _SessionsSection({
    required this.hourlyMinutes,
    required this.bestFocusWindow,
    required this.avgFocusPerSession,
    required this.avgFocusPerDay,
  });

  @override
  State<_SessionsSection> createState() => _SessionsSectionState();
}

class _SessionsSectionState extends State<_SessionsSection> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final windows = List.generate(6, (i) {
      int sum = 0;
      for (int h = i * 4; h < (i + 1) * 4; h++) {
        sum += widget.hourlyMinutes[h] ?? 0;
      }
      return sum;
    });
    final maxW = windows.fold<int>(1, (a, b) => a > b ? a : b);
    final peakIdx = windows.indexWhere((v) => v == maxW);
    final avgFsMin = widget.avgFocusPerSession.round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Sessions',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF18181B),
              ),
            ),
            _SegmentPill(
              labels: const ['All Day', 'AM', 'PM'],
              selected: _selected,
              onChanged: (v) => setState(() => _selected = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8FA),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InlineMetric(
                    value: _formatDuration(avgFsMin),
                    label: 'Avg Focus / s',
                  ),
                  // TODO: real avg break time — currently mocked alongside screen-time data.
                  _InlineMetric(value: '4m', label: 'Avg Break / s'),
                  _InlineMetric(
                    value: _formatDuration(widget.avgFocusPerDay),
                    label: 'Avg Focus / d',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 90,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (i) {
                        final val = windows[i];
                        final barH = maxW == 0
                            ? 4.0
                            : (val / maxW * 72).clamp(4.0, 72.0);
                        final isPeak = i == peakIdx && val > 0;
                        return Container(
                          width: 28,
                          height: barH,
                          decoration: BoxDecoration(
                            gradient: isPeak
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF4F46E5),
                                      Color(0xFF7C3AED),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  )
                                : null,
                            color:
                                isPeak ? null : const Color(0xFFA5B4FC),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['00', '04', '08', '12', '16', '20', '24']
                        .map(
                          (l) => Text(
                            l,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department,
                            size: 16, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Text(
                          'Best Focus Time',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF4F46E5),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      widget.bestFocusWindow,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF4F46E5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Screen Time section
// ---------------------------------------------------------------------------

class _ScreenTimeSection extends StatelessWidget {
  final int screenTimeTotalMinutes;
  final int screenTimeDuringFocus;
  final int screenTimeAfterFocus;
  final List<({String app, int beforeMin, int afterMin})> appUsage;

  const _ScreenTimeSection({
    required this.screenTimeTotalMinutes,
    required this.screenTimeDuringFocus,
    required this.screenTimeAfterFocus,
    required this.appUsage,
  });

  @override
  Widget build(BuildContext context) {
    final apps = appUsage.take(3).toList();
    final maxBefore =
        apps.fold<int>(1, (m, a) => a.beforeMin > m ? a.beforeMin : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Screen Time',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF18181B),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  const Icon(Icons.add_rounded,
                      size: 12, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    'Choose app',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                value: _formatDuration(screenTimeTotalMinutes),
                valueColor: const Color(0xFF16A34A),
                label: 'Total',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniStatCard(
                value: _formatDuration(screenTimeDuringFocus),
                valueColor: const Color(0xFF4F46E5),
                label: 'During Focus',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniStatCard(
                value: _formatDuration(screenTimeAfterFocus),
                valueColor: const Color(0xFFDC2626),
                label: 'Avg after F',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8FA),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Before vs After Focus',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF18181B),
                    ),
                  ),
                  Row(
                    children: [
                      _LegendSquare(
                          color: const Color(0xFFDC2626),
                          label: 'Before'),
                      const SizedBox(width: 8),
                      _LegendSquare(
                          color: const Color(0xFF16A34A),
                          label: 'After'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...apps.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AppUsageRow(
                    app: a.app,
                    beforeMin: a.beforeMin,
                    afterMin: a.afterMin,
                    maxBefore: maxBefore,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppUsageRow extends StatelessWidget {
  final String app;
  final int beforeMin;
  final int afterMin;
  final int maxBefore;

  const _AppUsageRow({
    required this.app,
    required this.beforeMin,
    required this.afterMin,
    required this.maxBefore,
  });

  Color _appColor(String name) {
    final n = name.toLowerCase();
    if (n.contains('youtube')) return const Color(0xFFFF0000);
    if (n.contains('tik') || n.startsWith('x')) {
      return const Color(0xFF000000);
    }
    return const Color(0xFF6366F1);
  }

  @override
  Widget build(BuildContext context) {
    final letter = app.isNotEmpty ? app[0].toUpperCase() : '?';
    final color = _appColor(app);
    final total = beforeMin + afterMin;
    final beforePct =
        maxBefore == 0 ? 0.0 : (beforeMin / maxBefore).clamp(0.0, 1.0);
    final maxAll = beforeMin > afterMin ? beforeMin : afterMin;
    final afterPct =
        maxAll == 0 ? 0.0 : (afterMin / maxAll).clamp(0.0, 1.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            letter,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    app,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF18181B),
                    ),
                  ),
                  Text(
                    _formatDuration(total),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _ProgressBar(
                pct: beforePct,
                trackColor: const Color(0xFFFEE2E2),
                fillColor: const Color(0xFFDC2626),
              ),
              const SizedBox(height: 3),
              _ProgressBar(
                pct: afterPct,
                trackColor: const Color(0xFFDCFCE7),
                fillColor: const Color(0xFF16A34A),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double pct;
  final Color trackColor;
  final Color fillColor;

  const _ProgressBar({
    required this.pct,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final fillW =
          (constraints.maxWidth * pct.clamp(0.0, 1.0)).clamp(0.0, constraints.maxWidth);
      return Container(
        height: 6,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: fillW,
            height: 6,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _MiniStatCard extends StatelessWidget {
  final String value;
  final Color valueColor;
  final String label;
  final double valueFontSize;

  const _MiniStatCard({
    required this.value,
    required this.valueColor,
    required this.label,
    this.valueFontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  final String value;
  final String label;

  const _InlineMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF18181B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

class _LegendSquare extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendSquare({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const _SegmentPill({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final isActive = i == selected;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color:
                    isActive ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                labels[i],
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isActive
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: isActive
                      ? const Color(0xFF18181B)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
