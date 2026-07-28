import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../logic/formatters.dart';
import '../models/profile_stats.dart';

class BestWeekCard extends StatelessWidget {
  final BestWeek? bestWeek;

  const BestWeekCard({super.key, this.bestWeek});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: bestWeek == null ? _empty() : _filled(bestWeek!),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.emoji_events_outlined,
            size: 20,
            color: Color(0xFF7C3AED),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Best Week',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        Text(
          'Start a focus session to unlock records',
          style: AppTypography.body14(color: AppColors.textLight),
        ),
      ],
    );
  }

  Widget _filled(BestWeek week) {
    final perDay = week.perDay.length >= 7 ? week.perDay.sublist(0, 7) : [
      ...week.perDay,
      ...List.filled(7 - week.perDay.length, 0),
    ];

    final maxVal = perDay.fold<int>(0, (m, v) => v > m ? v : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        Text(
          formatHoursMinutes(week.totalSeconds),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatWeekRange(week.weekStart),
          style: AppTypography.caption12(color: AppColors.textLight),
        ),
        const SizedBox(height: 14),
        _BarChart(perDay: perDay, maxVal: maxVal),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<int> perDay;
  final int maxVal;

  const _BarChart({required this.perDay, required this.maxVal});

  @override
  Widget build(BuildContext context) {
    const barHeight = 40.0;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final val = perDay[i];
        final ratio = (maxVal > 0) ? val / maxVal : 0.0;
        final barH = (ratio * barHeight).clamp(3.0, barHeight);
        final isActive = val > 0;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 6 ? 4 : 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: barH,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
