import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/statistics_state.dart';
import '../../providers/statistics_provider.dart';

String _formatDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String _shortMonth(int month) => [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][month - 1];

String _fmtDateRange(DateTime monday) {
  final sunday = monday.add(const Duration(days: 6));
  return '${monday.day} - ${sunday.day} ${_shortMonth(sunday.month)}';
}

class StatsCompPage extends ConsumerWidget {
  const StatsCompPage({super.key});

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
            _CompareHeader(),
            const SizedBox(height: 14),
            _CompareCard(
              thisWeek: stats.thisWeekSummary,
              lastWeek: stats.lastWeekSummary,
            ),
            const SizedBox(height: 14),
            _TotalChangeBanner(
              totalChangePct: stats.totalChangePct,
              totalChangeLabel: stats.totalChangeLabel,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compare header
// ---------------------------------------------------------------------------

class _CompareHeader extends StatelessWidget {
  const _CompareHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Compare',
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
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              Text(
                'This week',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more,
                  size: 12, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Compare card
// ---------------------------------------------------------------------------

class _CompareCard extends StatelessWidget {
  final WeekSummary thisWeek;
  final WeekSummary lastWeek;

  const _CompareCard({required this.thisWeek, required this.lastWeek});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _WeekColumn(summary: thisWeek, isDimmed: false),
            ),
            Container(
              width: 1,
              color: const Color(0xFFE5E7EB),
            ),
            Expanded(
              child: _WeekColumn(summary: lastWeek, isDimmed: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekColumn extends StatelessWidget {
  final WeekSummary summary;
  final bool isDimmed;

  const _WeekColumn({required this.summary, required this.isDimmed});

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDimmed ? const Color(0xFF94A3B8) : const Color(0xFF18181B);
    final labelColor = const Color(0xFF94A3B8);
    final ffScore = (summary.focusFormScore / 10.0).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Week label
          Text(
            'Week',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF94A3B8),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _fmtDateRange(summary.weekStart),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isDimmed
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF18181B),
            ),
          ),
          const SizedBox(height: 10),
          // Focus Form card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ffScore,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Focus Form',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: labelColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Metrics list
          _MetricRow(
            value: _formatDuration(summary.allFocusMinutes),
            label: 'All Focus',
            textColor: textColor,
            labelColor: labelColor,
          ),
          const SizedBox(height: 14),
          _MetricRow(
            value: _formatDuration(summary.avgFocusMinutesPerDay),
            label: 'Avg Focus / d',
            textColor: textColor,
            labelColor: labelColor,
          ),
          const SizedBox(height: 14),
          _MetricRow(
            value: _formatDuration(summary.avgFocusMinutesPerSession.round()),
            label: 'Avg Focus / s',
            textColor: textColor,
            labelColor: labelColor,
          ),
          const SizedBox(height: 14),
          _MetricRow(
            value: '${summary.sessions}',
            label: 'Sessions',
            textColor: textColor,
            labelColor: labelColor,
          ),
          const SizedBox(height: 14),
          _MetricRow(
            value: '${summary.focusDays} / ${summary.focusDaysGoal}',
            label: 'Focus Days',
            textColor: textColor,
            labelColor: labelColor,
          ),
          const SizedBox(height: 14),
          _MetricRow(
            value: _formatDuration(summary.screenTimeMinutes),
            label: 'Screen Time',
            textColor: textColor,
            labelColor: labelColor,
          ),
          const SizedBox(height: 14),
          _RhythmRow(
            rhythmScore: summary.rhythmScore,
            labelColor: labelColor,
            isDimmed: isDimmed,
          ),
          const SizedBox(height: 14),
          _MetricRow(
            value: '${summary.planCompletePct}%',
            label: 'Plan Complete',
            textColor: isDimmed
                ? const Color(0xFF94A3B8)
                : const Color(0xFF4F46E5),
            labelColor: labelColor,
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String value;
  final String label;
  final Color textColor;
  final Color labelColor;

  const _MetricRow({
    required this.value,
    required this.label,
    required this.textColor,
    required this.labelColor,
  });

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
            color: textColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}

class _RhythmRow extends StatelessWidget {
  final int rhythmScore;
  final Color labelColor;
  final bool isDimmed;

  const _RhythmRow({
    required this.rhythmScore,
    required this.labelColor,
    required this.isDimmed,
  });

  @override
  Widget build(BuildContext context) {
    // 5 mini bars representing rhythm (score 0-100)
    // Heights vary based on score distribution (simple visual)
    final baseH = (rhythmScore / 100 * 16).clamp(2.0, 16.0);
    final heights = [
      baseH * 0.5,
      baseH * 0.75,
      baseH,
      baseH * 0.75,
      baseH * 0.5,
    ];
    final barColor = isDimmed
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF6366F1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(5, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i < 4 ? 3 : 0),
              child: Container(
                width: 8,
                height: heights[i].clamp(2.0, 16.0),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 2),
        Text(
          'Rhythm',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Total change banner
// ---------------------------------------------------------------------------

class _TotalChangeBanner extends StatelessWidget {
  final int totalChangePct;
  final String totalChangeLabel;

  const _TotalChangeBanner({
    required this.totalChangePct,
    required this.totalChangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final List<Color> gradientColors;
    if (totalChangePct > 0) {
      gradientColors = [const Color(0xFF16A34A), const Color(0xFF22C55E)];
    } else if (totalChangePct < 0) {
      gradientColors = [const Color(0xFFDC2626), const Color(0xFFEF4444)];
    } else {
      gradientColors = [const Color(0xFF64748B), const Color(0xFF94A3B8)];
    }

    final icon = totalChangePct >= 0
        ? Icons.trending_up
        : Icons.trending_down;
    final sign = totalChangePct > 0 ? '+' : '';
    final pctLabel = '$sign$totalChangePct%';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total change',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xCCFFFFFF),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                totalChangeLabel,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                pctLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
